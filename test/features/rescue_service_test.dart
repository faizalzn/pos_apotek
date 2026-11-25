import 'package:flutter_test/flutter_test.dart';
import 'package:pos_apotek/core/config.dart';
import 'package:pos_apotek/core/database/app_database.dart';
import 'package:pos_apotek/core/security/rescue_code.dart';
import 'package:pos_apotek/features/auth/data/recovery_code_service.dart';
import 'package:pos_apotek/features/auth/data/rescue_service.dart';
import 'package:pos_apotek/features/auth/data/user_repository.dart';
import 'package:pos_apotek/features/settings/data/settings_repository.dart';

import '../helpers.dart';

void main() {
  late AppDatabase db;
  late FakeClock clock;
  late UserRepository users;
  late RecoveryCodeService recovery;
  late RescueService rescue;
  late String privateKey;
  late AppUser owner;

  setUp(() async {
    final keys = await RescueCode.generateKeys();
    privateKey = keys.privateKey;
    db = memoryDatabase();
    clock = FakeClock();
    final settings = SettingsRepository(db, clock.call);
    users = UserRepository(db, fastHasher, clock.call);
    recovery = RecoveryCodeService(settings, users, fastHasher);
    rescue = RescueService(
      settings,
      users,
      recovery,
      AppConfig(
        rescuePublicKey: keys.publicKey,
        developerWhatsApp: '0812-3456-7890',
      ),
      clock.call,
    );
    owner = await users.create(
      name: 'Pemilik',
      role: UserRole.owner,
      pin: '482915',
    );
  });

  tearDown(() => db.close());

  Future<String> replyFor(String challenge) =>
      RescueCode.sign(challenge: challenge, privateKey: privateKey);

  test('kode tantangan tetap sama sampai kedaluwarsa', () async {
    final first = await rescue.currentChallenge();
    clock.advance(const Duration(hours: 23));
    expect(await rescue.currentChallenge(), first);
    clock.advance(const Duration(hours: 2));
    expect(await rescue.currentChallenge(), isNot(first));
  });

  test('balasan sah mengatur PIN baru dan memberi kode pemulihan baru', () async {
    final challenge = await rescue.currentChallenge();
    final reply = await replyFor(challenge);

    final newRecovery = await rescue.resetOwnerPin(
      replyText: reply,
      ownerId: owner.id,
      newPin: '739164',
    );

    expect(newRecovery, isNotNull);
    expect(await recovery.verify(newRecovery!), isTrue);
    expect(await users.checkPin(owner.id, '739164'), isA<PinAccepted>());
  });

  test('balasan hanya bisa dipakai sekali', () async {
    final challenge = await rescue.currentChallenge();
    final reply = await replyFor(challenge);
    await rescue.resetOwnerPin(
      replyText: reply,
      ownerId: owner.id,
      newPin: '739164',
    );
    expect(await rescue.verifyReply(reply), isFalse);
    expect(
      await rescue.resetOwnerPin(
        replyText: reply,
        ownerId: owner.id,
        newPin: '582047',
      ),
      isNull,
    );
  });

  test('balasan kedaluwarsa setelah 24 jam', () async {
    final challenge = await rescue.currentChallenge();
    final reply = await replyFor(challenge);
    clock.advance(const Duration(hours: 25));
    expect(await rescue.verifyReply(reply), isFalse);
  });

  test('tidak bisa dipakai untuk akun Kasir', () async {
    final kasir = await users.create(
      name: 'Kasir',
      role: UserRole.cashier,
      pin: '482915',
    );
    final reply = await replyFor(await rescue.currentChallenge());
    expect(
      () => rescue.resetOwnerPin(
        replyText: reply,
        ownerId: kasir.id,
        newPin: '739164',
      ),
      throwsA(isA<UserRuleException>()),
    );
  });

  test('tautan WhatsApp memakai nomor yang dinormalisasi', () {
    final link = rescue.whatsAppLink('Kode tantangan: ABCD-EFGH')!;
    expect(link.host, 'wa.me');
    expect(link.path, '/6281234567890');
    expect(link.queryParameters['text'], 'Kode tantangan: ABCD-EFGH');
  });
}
