import 'package:flutter_test/flutter_test.dart';
import 'package:pos_apotek/core/database/app_database.dart';
import 'package:pos_apotek/features/auth/data/recovery_code_service.dart';
import 'package:pos_apotek/features/auth/data/user_repository.dart';
import 'package:pos_apotek/features/settings/data/settings_repository.dart';
import 'package:pos_apotek/features/setup/data/setup_service.dart';

import '../helpers.dart';

void main() {
  late AppDatabase db;
  late SettingsRepository settings;
  late UserRepository users;
  late RecoveryCodeService recovery;
  late SetupService setup;

  setUp(() {
    db = memoryDatabase();
    final clock = FakeClock();
    settings = SettingsRepository(db, clock.call);
    users = UserRepository(db, fastHasher, clock.call);
    recovery = RecoveryCodeService(settings, users, fastHasher);
    setup = SetupService(db, settings, users, recovery);
  });

  tearDown(() => db.close());

  Future<SetupResult> runSetup() => setup.complete(
        store: const StoreProfile(name: 'Apotek Contoh', address: 'Jl. Desa 1'),
        ownerName: 'Pemilik',
        ownerPin: '482915',
      );

  test('menyimpan profil apotek, pemilik, dan menandai selesai', () async {
    expect(await settings.isSetupCompleted(), isFalse);
    final result = await runSetup();

    expect(await settings.isSetupCompleted(), isTrue);
    expect(result.owner.role, UserRole.owner);
    final profile = await settings.watchStoreProfile().first;
    expect(profile.name, 'Apotek Contoh');
    expect(profile.address, 'Jl. Desa 1');
    expect(profile.receiptFooter, StoreProfile.defaultReceiptFooter);
    expect(result.recoveryCode, matches(RegExp(r'^[A-Z0-9]{4}-[A-Z0-9]{4}$')));
  });

  test('tidak bisa dijalankan dua kali', () async {
    await runSetup();
    expect(runSetup, throwsA(isA<UserRuleException>()));
  });

  test('gagal di tengah jalan tidak meninggalkan data setengah jadi', () async {
    await expectLater(
      setup.complete(
        store: const StoreProfile(name: 'Apotek Contoh'),
        ownerName: 'Pemilik',
        ownerPin: '111111', // PIN lemah → ditolak
      ),
      throwsA(isA<UserRuleException>()),
    );
    expect(await settings.isSetupCompleted(), isFalse);
    expect(await settings.get(SettingKeys.storeName), isNull);
  });

  group('kode pemulihan', () {
    test('diterima tanpa peduli huruf kecil/spasi/strip', () async {
      final result = await runSetup();
      final messy = ' ${result.recoveryCode.toLowerCase().replaceAll('-', ' ')} ';
      expect(await recovery.verify(messy), isTrue);
      expect(await recovery.verify('AAAA-AAAA'), isFalse);
    });

    test('mengatur ulang PIN pemilik dan menghanguskan kode lama', () async {
      final result = await runSetup();
      final newCode = await recovery.resetOwnerPin(
        code: result.recoveryCode,
        ownerId: result.owner.id,
        newPin: '739164',
      );
      expect(newCode, isNotNull);
      expect(newCode, isNot(result.recoveryCode));
      expect(
        await users.checkPin(result.owner.id, '739164'),
        isA<PinAccepted>(),
      );
      expect(await recovery.verify(result.recoveryCode), isFalse);
      expect(await recovery.verify(newCode!), isTrue);
    });

    test('kode salah tidak mengubah PIN', () async {
      final result = await runSetup();
      final newCode = await recovery.resetOwnerPin(
        code: 'AAAA-AAAA',
        ownerId: result.owner.id,
        newPin: '739164',
      );
      expect(newCode, isNull);
      expect(
        await users.checkPin(result.owner.id, '482915'),
        isA<PinAccepted>(),
      );
    });
  });
}
