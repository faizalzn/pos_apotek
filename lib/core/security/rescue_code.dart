// Logika kode darurat developer (tanpa Flutter), dipakai bersama oleh
// aplikasi dan alat baris perintah `tool/kode_darurat.dart`.
//
// Cara kerja (lihat docs/decisions/0009-kode-darurat-developer.md):
// 1. Aplikasi membuat kode tantangan acak, mis. `7K3M-Q9TX`.
// 2. Developer menandatangani tantangan itu dengan kunci privat Ed25519.
// 3. Aplikasi memeriksa tanda tangan dengan kunci publik yang tertanam.
// Hanya pemegang kunci privat yang bisa membuat kode balasan yang sah.

import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

abstract final class RescueCode {
  static const _alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  static const _context = 'POSAPOTEK-RESCUE-v1:';
  static final _random = Random.secure();
  static final _ed25519 = Ed25519();

  /// Panjang kode balasan (tanda tangan 64 byte dalam base64url tanpa `=`).
  static const replyLength = 86;

  /// Membuat kode tantangan baru dalam format tampilan `ABCD-EFGH`.
  static String newChallenge() {
    final raw = List.generate(
      8,
      (_) => _alphabet[_random.nextInt(_alphabet.length)],
    ).join();
    return '${raw.substring(0, 4)}-${raw.substring(4)}';
  }

  /// Huruf besar, tanpa spasi/strip. Mengembalikan `null` bila bukan kode
  /// tantangan yang sah.
  static String? normalizeChallenge(String input) {
    final raw = input.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
    if (raw.length != 8 || raw.split('').any((c) => !_alphabet.contains(c))) {
      return null;
    }
    return raw;
  }

  static List<int> _message(String normalizedChallenge) =>
      utf8.encode('$_context$normalizedChallenge');

  /// Mengambil kode balasan dari teks yang ditempel (boleh berisi seluruh
  /// pesan WhatsApp, bukan hanya kodenya).
  static String? extractReply(String text) {
    final match = RegExp('[A-Za-z0-9_-]{$replyLength}').firstMatch(text);
    return match?.group(0);
  }

  /// Membuat pasangan kunci baru. Mengembalikan (kunci privat, kunci publik)
  /// dalam base64.
  static Future<({String privateKey, String publicKey})> generateKeys() async {
    final pair = await _ed25519.newKeyPair();
    final seed = await pair.extractPrivateKeyBytes();
    final public = await pair.extractPublicKey();
    return (privateKey: base64Encode(seed), publicKey: base64Encode(public.bytes));
  }

  /// Kunci publik yang sesuai dengan [privateKey] (base64).
  static Future<String> publicKeyOf(String privateKey) async {
    final pair = await _ed25519.newKeyPairFromSeed(base64Decode(privateKey));
    return base64Encode((await pair.extractPublicKey()).bytes);
  }

  /// Developer: membuat kode balasan untuk [challenge].
  static Future<String> sign({
    required String challenge,
    required String privateKey,
  }) async {
    final normalized = normalizeChallenge(challenge);
    if (normalized == null) {
      throw FormatException('Kode tantangan tidak valid: $challenge');
    }
    final pair = await _ed25519.newKeyPairFromSeed(base64Decode(privateKey));
    final signature = await _ed25519.sign(_message(normalized), keyPair: pair);
    return base64Url.encode(signature.bytes).replaceAll('=', '');
  }

  /// Aplikasi: memeriksa apakah [reply] adalah balasan sah untuk [challenge].
  static Future<bool> verify({
    required String challenge,
    required String reply,
    required String publicKey,
  }) async {
    final normalized = normalizeChallenge(challenge);
    final code = extractReply(reply);
    if (normalized == null || code == null || publicKey.isEmpty) return false;
    try {
      final signatureBytes = base64Url.decode('$code==');
      final publicBytes = base64Decode(publicKey);
      if (signatureBytes.length != 64 || publicBytes.length != 32) return false;
      return await _ed25519.verify(
        _message(normalized),
        signature: Signature(
          signatureBytes,
          publicKey: SimplePublicKey(publicBytes, type: KeyPairType.ed25519),
        ),
      );
    } on Object {
      return false;
    }
  }
}
