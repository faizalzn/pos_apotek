import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/clock.dart';
import '../../../core/database/app_database.dart';
import '../../../core/security/pin_hasher.dart';

/// Pelanggaran aturan bisnis pengguna. [message] siap ditampilkan ke pengguna.
class UserRuleException implements Exception {
  const UserRuleException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Hasil pengecekan PIN.
sealed class PinCheckResult {
  const PinCheckResult();
}

class PinAccepted extends PinCheckResult {
  const PinAccepted(this.user);
  final AppUser user;
}

class PinRejected extends PinCheckResult {
  const PinRejected({required this.attemptsLeft});

  /// Sisa percobaan sebelum dikunci sementara.
  final int attemptsLeft;
}

class PinLocked extends PinCheckResult {
  const PinLocked(this.remaining);
  final Duration remaining;
}

/// Aturan penguncian setelah salah PIN berkali-kali.
///
/// Setiap kelipatan [maxAttempts] kesalahan, akun dikunci selama
/// [baseLock] × 2^(n-1), maksimal [maxLock].
class LockoutPolicy {
  const LockoutPolicy({
    this.maxAttempts = 5,
    this.baseLock = const Duration(seconds: 30),
    this.maxLock = const Duration(minutes: 15),
  });

  final int maxAttempts;
  final Duration baseLock;
  final Duration maxLock;

  /// Lama penguncian setelah total [failedAttempts] kesalahan, atau `null`
  /// bila belum perlu dikunci.
  Duration? lockFor(int failedAttempts) {
    if (failedAttempts == 0 || failedAttempts % maxAttempts != 0) return null;
    final round = failedAttempts ~/ maxAttempts;
    final ms = baseLock.inMilliseconds * (1 << (round - 1).clamp(0, 20));
    return Duration(milliseconds: ms.clamp(0, maxLock.inMilliseconds));
  }

  int attemptsLeft(int failedAttempts) =>
      maxAttempts - (failedAttempts % maxAttempts);
}

final _pinPattern = RegExp('^\\d{$pinLength}\$');

/// Menolak PIN yang terlalu mudah ditebak. Mengembalikan pesan kesalahan,
/// atau `null` bila PIN boleh dipakai.
String? validateNewPin(String pin) {
  if (!_pinPattern.hasMatch(pin)) return 'PIN harus $pinLength angka';
  if (pin.split('').toSet().length == 1) {
    return 'PIN terlalu mudah ditebak (semua angka sama)';
  }
  const ascending = '0123456789';
  const descending = '9876543210';
  if (ascending.contains(pin) || descending.contains(pin)) {
    return 'PIN terlalu mudah ditebak (angka berurutan)';
  }
  return null;
}

class UserRepository {
  UserRepository(
    this._db,
    this._hasher,
    this._now, {
    this.lockout = const LockoutPolicy(),
  });

  final AppDatabase _db;
  final PinHasher _hasher;
  final Clock _now;
  final LockoutPolicy lockout;

  static const _uuid = Uuid();

  /// Semua pengguna: Pemilik dulu, lalu urut nama.
  Stream<List<AppUser>> watchAll() => (_db.select(_db.users)
        ..orderBy([
          (u) => OrderingTerm.desc(u.role),
          (u) => OrderingTerm.asc(u.name),
        ]))
      .watch();

  Stream<List<AppUser>> watchActive() =>
      watchAll().map((list) => list.where((u) => u.isActive).toList());

  Future<AppUser?> byId(String id) =>
      (_db.select(_db.users)..where((u) => u.id.equals(id)))
          .getSingleOrNull();

  Future<AppUser> create({
    required String name,
    required UserRole role,
    required String pin,
  }) async {
    final cleanName = await _validateName(name);
    final pinError = validateNewPin(pin);
    if (pinError != null) throw UserRuleException(pinError);

    final salt = _hasher.newSalt();
    final hash = await _hasher.hash(pin, salt);
    final now = _now();
    final id = _uuid.v4();
    await _db.into(_db.users).insert(
          UsersCompanion.insert(
            id: id,
            name: cleanName,
            role: role,
            pinHash: hash,
            pinSalt: salt,
            createdAt: now,
            updatedAt: now,
          ),
        );
    return (await byId(id))!;
  }

  /// Memeriksa PIN, mencatat kesalahan, dan menerapkan penguncian.
  Future<PinCheckResult> checkPin(String userId, String pin) async {
    final user = await byId(userId);
    if (user == null || !user.isActive) {
      throw const UserRuleException('Pengguna tidak ditemukan atau nonaktif');
    }
    final now = _now();
    final lockedUntil = user.lockedUntil;
    if (lockedUntil != null && lockedUntil.isAfter(now)) {
      return PinLocked(lockedUntil.difference(now));
    }

    if (await _hasher.verify(pin, user.pinSalt, user.pinHash)) {
      if (user.failedAttempts != 0 || user.lockedUntil != null) {
        await _update(
          userId,
          const UsersCompanion(
            failedAttempts: Value(0),
            lockedUntil: Value(null),
          ),
        );
      }
      return PinAccepted((await byId(userId))!);
    }

    final failed = user.failedAttempts + 1;
    final lockDuration = lockout.lockFor(failed);
    await _update(
      userId,
      UsersCompanion(
        failedAttempts: Value(failed),
        lockedUntil: Value(lockDuration == null ? null : now.add(lockDuration)),
      ),
    );
    if (lockDuration != null) return PinLocked(lockDuration);
    return PinRejected(attemptsLeft: lockout.attemptsLeft(failed));
  }

  /// Mengganti PIN dan membuka penguncian.
  Future<void> setPin(String userId, String pin) async {
    final pinError = validateNewPin(pin);
    if (pinError != null) throw UserRuleException(pinError);
    final salt = _hasher.newSalt();
    final hash = await _hasher.hash(pin, salt);
    await _update(
      userId,
      UsersCompanion(
        pinHash: Value(hash),
        pinSalt: Value(salt),
        failedAttempts: const Value(0),
        lockedUntil: const Value(null),
      ),
    );
  }

  Future<void> rename(String userId, String name) async {
    final cleanName = await _validateName(name, exceptId: userId);
    await _update(userId, UsersCompanion(name: Value(cleanName)));
  }

  /// Mengaktifkan/menonaktifkan pengguna. Pemilik aktif terakhir tidak boleh
  /// dinonaktifkan agar aplikasi tidak terkunci.
  Future<void> setActive(String userId, {required bool active}) async {
    final user = await byId(userId);
    if (user == null) return;
    if (!active && user.role == UserRole.owner) {
      final owners = await (_db.select(_db.users)
            ..where(
              (u) => u.role.equalsValue(UserRole.owner) & u.isActive,
            ))
          .get();
      if (owners.length <= 1) {
        throw const UserRuleException(
          'Pemilik terakhir tidak bisa dinonaktifkan',
        );
      }
    }
    if (active) {
      await _validateName(user.name, exceptId: userId);
    }
    await _update(userId, UsersCompanion(isActive: Value(active)));
  }

  Future<void> _update(String userId, UsersCompanion changes) =>
      (_db.update(_db.users)..where((u) => u.id.equals(userId)))
          .write(changes.copyWith(updatedAt: Value(_now())));

  Future<String> _validateName(String name, {String? exceptId}) async {
    final clean = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (clean.isEmpty) throw const UserRuleException('Nama wajib diisi');
    if (clean.length > 50) {
      throw const UserRuleException('Nama maksimal 50 karakter');
    }
    final query = _db.select(_db.users)
      ..where(
        (u) => u.name.lower().equals(clean.toLowerCase()) & u.isActive,
      );
    final same = await query.get();
    if (same.any((u) => u.id != exceptId)) {
      throw UserRuleException('Nama "$clean" sudah dipakai pengguna lain');
    }
    return clean;
  }
}

final userRepositoryProvider = Provider<UserRepository>(
  (ref) => UserRepository(
    ref.watch(databaseProvider),
    ref.watch(pinHasherProvider),
    ref.watch(clockProvider),
  ),
);

final allUsersProvider = StreamProvider<List<AppUser>>(
  (ref) => ref.watch(userRepositoryProvider).watchAll(),
);

final activeUsersProvider = StreamProvider<List<AppUser>>(
  (ref) => ref.watch(userRepositoryProvider).watchActive(),
);
