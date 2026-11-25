import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/security/pin_hasher.dart';
import '../../settings/data/settings_repository.dart';
import 'user_repository.dart';

/// Kode pemulihan untuk Pemilik yang lupa PIN.
///
/// Kode ditampilkan sekali saat setup (dan setiap kali dibuat ulang); yang
/// disimpan hanya hash-nya. Setelah dipakai, kode lama hangus dan kode baru
/// diberikan.
class RecoveryCodeService {
  RecoveryCodeService(this._settings, this._users, this._hasher);

  final SettingsRepository _settings;
  final UserRepository _users;
  final PinHasher _hasher;

  /// Tanpa huruf/angka yang mirip (0/O, 1/I/L) agar tidak salah baca.
  static const _alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  static final _random = Random.secure();

  /// Format tampilan: `ABCD-EFGH`.
  static String format(String normalized) =>
      '${normalized.substring(0, 4)}-${normalized.substring(4)}';

  /// Menghapus spasi/strip dan menjadikan huruf besar.
  static String normalize(String input) =>
      input.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');

  /// Membuat kode baru (kode lama tidak berlaku lagi) dan mengembalikan
  /// kode dalam format tampilan.
  Future<String> issueNew() async {
    final code = List.generate(
      8,
      (_) => _alphabet[_random.nextInt(_alphabet.length)],
    ).join();
    final salt = _hasher.newSalt();
    final hash = await _hasher.hash(code, salt);
    await _settings.setAll({
      SettingKeys.recoveryHash: hash,
      SettingKeys.recoverySalt: salt,
    });
    return format(code);
  }

  Future<bool> verify(String input) async {
    final code = normalize(input);
    if (code.length != 8) return false;
    final hash = await _settings.get(SettingKeys.recoveryHash);
    final salt = await _settings.get(SettingKeys.recoverySalt);
    if (hash == null || salt == null) return false;
    return _hasher.verify(code, salt, hash);
  }

  /// Mengatur ulang PIN Pemilik memakai kode pemulihan.
  ///
  /// Mengembalikan kode pemulihan **baru**, atau `null` bila kode salah.
  Future<String?> resetOwnerPin({
    required String code,
    required String ownerId,
    required String newPin,
  }) async {
    if (!await verify(code)) return null;
    final owner = await _users.byId(ownerId);
    if (owner == null || owner.role != UserRole.owner) {
      throw const UserRuleException('Kode pemulihan hanya untuk Pemilik');
    }
    await _users.setPin(ownerId, newPin);
    return issueNew();
  }
}

final recoveryCodeServiceProvider = Provider<RecoveryCodeService>(
  (ref) => RecoveryCodeService(
    ref.watch(settingsRepositoryProvider),
    ref.watch(userRepositoryProvider),
    ref.watch(pinHasherProvider),
  ),
);
