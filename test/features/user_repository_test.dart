import 'package:flutter_test/flutter_test.dart';
import 'package:pos_apotek/core/database/app_database.dart';
import 'package:pos_apotek/features/auth/data/user_repository.dart';

import '../helpers.dart';

void main() {
  late AppDatabase db;
  late FakeClock clock;
  late UserRepository repo;

  setUp(() {
    db = memoryDatabase();
    clock = FakeClock();
    repo = UserRepository(db, fastHasher, clock.call);
  });

  tearDown(() => db.close());

  group('validateNewPin', () {
    test('menolak PIN yang bukan 6 angka', () {
      expect(validateNewPin('12345'), isNotNull);
      expect(validateNewPin('12345a'), isNotNull);
      expect(validateNewPin('1234567'), isNotNull);
    });

    test('menolak PIN yang mudah ditebak', () {
      expect(validateNewPin('111111'), isNotNull);
      expect(validateNewPin('123456'), isNotNull);
      expect(validateNewPin('987654'), isNotNull);
    });

    test('menerima PIN yang wajar', () {
      expect(validateNewPin('482915'), isNull);
    });
  });

  group('create', () {
    test('menyimpan pengguna tanpa menyimpan PIN asli', () async {
      final user = await repo.create(
        name: '  Rina   Sari ',
        role: UserRole.cashier,
        pin: '482915',
      );
      expect(user.name, 'Rina Sari');
      expect(user.role, UserRole.cashier);
      expect(user.isActive, isTrue);
      expect(user.pinHash, isNot(contains('482915')));
    });

    test('menolak nama ganda (tidak peka huruf besar/kecil)', () async {
      await repo.create(name: 'Rina', role: UserRole.cashier, pin: '482915');
      expect(
        () => repo.create(name: 'rina', role: UserRole.cashier, pin: '482915'),
        throwsA(isA<UserRuleException>()),
      );
    });

    test('menolak nama kosong dan PIN lemah', () async {
      expect(
        () => repo.create(name: '  ', role: UserRole.cashier, pin: '482915'),
        throwsA(isA<UserRuleException>()),
      );
      expect(
        () => repo.create(name: 'Budi', role: UserRole.cashier, pin: '000000'),
        throwsA(isA<UserRuleException>()),
      );
    });
  });

  group('checkPin', () {
    late AppUser user;

    setUp(() async {
      user = await repo.create(
        name: 'Rina',
        role: UserRole.cashier,
        pin: '482915',
      );
    });

    test('PIN benar diterima', () async {
      expect(await repo.checkPin(user.id, '482915'), isA<PinAccepted>());
    });

    test('PIN salah mengurangi sisa percobaan', () async {
      final result = await repo.checkPin(user.id, '000001');
      expect(result, isA<PinRejected>());
      expect((result as PinRejected).attemptsLeft, 4);
    });

    test('5 kali salah mengunci 30 detik, lalu bisa dicoba lagi', () async {
      for (var i = 0; i < 4; i++) {
        expect(await repo.checkPin(user.id, '000001'), isA<PinRejected>());
      }
      final locked = await repo.checkPin(user.id, '000001');
      expect(locked, isA<PinLocked>());
      expect((locked as PinLocked).remaining, const Duration(seconds: 30));

      // Saat terkunci, PIN benar pun ditolak.
      expect(await repo.checkPin(user.id, '482915'), isA<PinLocked>());

      clock.advance(const Duration(seconds: 31));
      expect(await repo.checkPin(user.id, '482915'), isA<PinAccepted>());
      expect((await repo.byId(user.id))!.failedAttempts, 0);
    });

    test('penguncian berikutnya makin lama', () async {
      for (var i = 0; i < 5; i++) {
        await repo.checkPin(user.id, '000001');
      }
      clock.advance(const Duration(seconds: 31));
      for (var i = 0; i < 4; i++) {
        await repo.checkPin(user.id, '000001');
      }
      final locked = await repo.checkPin(user.id, '000001') as PinLocked;
      expect(locked.remaining, const Duration(minutes: 1));
    });

    test('setPin mengganti PIN dan membuka kunci', () async {
      for (var i = 0; i < 5; i++) {
        await repo.checkPin(user.id, '000001');
      }
      await repo.setPin(user.id, '739164');
      expect(await repo.checkPin(user.id, '482915'), isA<PinRejected>());
      expect(await repo.checkPin(user.id, '739164'), isA<PinAccepted>());
    });
  });

  group('setActive', () {
    test('pemilik terakhir tidak bisa dinonaktifkan', () async {
      final owner = await repo.create(
        name: 'Pemilik',
        role: UserRole.owner,
        pin: '482915',
      );
      expect(
        () => repo.setActive(owner.id, active: false),
        throwsA(isA<UserRuleException>()),
      );
    });

    test('kasir bisa dinonaktifkan dan hilang dari daftar login', () async {
      await repo.create(name: 'Pemilik', role: UserRole.owner, pin: '482915');
      final kasir = await repo.create(
        name: 'Rina',
        role: UserRole.cashier,
        pin: '482915',
      );
      await repo.setActive(kasir.id, active: false);
      final active = await repo.watchActive().first;
      expect(active.map((u) => u.name), ['Pemilik']);
    });

    test('daftar diurutkan: Pemilik dulu', () async {
      await repo.create(name: 'Andi', role: UserRole.cashier, pin: '482915');
      await repo.create(name: 'Zahra', role: UserRole.owner, pin: '482915');
      final all = await repo.watchAll().first;
      expect(all.map((u) => u.name), ['Zahra', 'Andi']);
    });
  });
}
