import 'package:flutter_test/flutter_test.dart';
import 'package:pos_apotek/core/security/rescue_code.dart';

void main() {
  late String privateKey;
  late String publicKey;

  setUpAll(() async {
    final keys = await RescueCode.generateKeys();
    privateKey = keys.privateKey;
    publicKey = keys.publicKey;
  });

  test('kode tantangan berformat ABCD-EFGH tanpa huruf mirip', () {
    for (var i = 0; i < 50; i++) {
      final c = RescueCode.newChallenge();
      expect(c, matches(RegExp(r'^[A-Z2-9]{4}-[A-Z2-9]{4}$')));
      expect(c, isNot(matches(RegExp('[01OIL]'))));
    }
  });

  test('balasan yang ditandatangani kunci privat diterima', () async {
    final reply = await RescueCode.sign(
      challenge: '7K3M-Q9TX',
      privateKey: privateKey,
    );
    expect(reply.length, RescueCode.replyLength);
    expect(
      await RescueCode.verify(
        challenge: '7k3m q9tx', // huruf kecil & spasi tetap dikenali
        reply: reply,
        publicKey: publicKey,
      ),
      isTrue,
    );
  });

  test('seluruh pesan WhatsApp boleh ditempel', () async {
    final reply = await RescueCode.sign(
      challenge: '7K3M-Q9TX',
      privateKey: privateKey,
    );
    final message = 'Kode darurat POS Apotek:\n$reply\n\nSalin pesan ini...';
    expect(
      await RescueCode.verify(
        challenge: '7K3M-Q9TX',
        reply: message,
        publicKey: publicKey,
      ),
      isTrue,
    );
  });

  test('balasan untuk tantangan lain ditolak', () async {
    final reply = await RescueCode.sign(
      challenge: '7K3M-Q9TX',
      privateKey: privateKey,
    );
    expect(
      await RescueCode.verify(
        challenge: '7K3M-Q9TY',
        reply: reply,
        publicKey: publicKey,
      ),
      isFalse,
    );
  });

  test('balasan dari kunci lain ditolak', () async {
    final other = await RescueCode.generateKeys();
    final reply = await RescueCode.sign(
      challenge: '7K3M-Q9TX',
      privateKey: other.privateKey,
    );
    expect(
      await RescueCode.verify(
        challenge: '7K3M-Q9TX',
        reply: reply,
        publicKey: publicKey,
      ),
      isFalse,
    );
  });

  test('balasan yang diubah satu karakter ditolak', () async {
    final reply = await RescueCode.sign(
      challenge: '7K3M-Q9TX',
      privateKey: privateKey,
    );
    final tampered =
        '${reply.substring(0, 10)}${reply[10] == 'A' ? 'B' : 'A'}${reply.substring(11)}';
    expect(
      await RescueCode.verify(
        challenge: '7K3M-Q9TX',
        reply: tampered,
        publicKey: publicKey,
      ),
      isFalse,
    );
  });

  test('teks sembarang dan kunci publik kosong ditolak tanpa error', () async {
    expect(
      await RescueCode.verify(
        challenge: '7K3M-Q9TX',
        reply: 'halo',
        publicKey: publicKey,
      ),
      isFalse,
    );
    expect(
      await RescueCode.verify(
        challenge: '7K3M-Q9TX',
        reply: 'A' * 86,
        publicKey: '',
      ),
      isFalse,
    );
  });

  test('publicKeyOf cocok dengan kunci yang dibuat', () async {
    expect(await RescueCode.publicKeyOf(privateKey), publicKey);
  });
}
