import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Panjang PIN yang dipakai di seluruh aplikasi.
const pinLength = 6;

/// Meng-hash PIN dengan PBKDF2-HMAC-SHA256 + salt acak.
///
/// PIN 6 angka hanya punya 1 juta kemungkinan, jadi pertahanan utamanya adalah
/// penguncian setelah beberapa kali salah (lihat `UserRepository`). Hash ini
/// mencegah PIN terbaca langsung bila file database disalin.
class PinHasher {
  const PinHasher({this.iterations = 20000, this.useIsolate = true});

  final int iterations;

  /// Jalankan hashing di isolate terpisah agar UI tidak tersendat.
  /// Dimatikan di pengujian widget.
  final bool useIsolate;

  static final _random = Random.secure();

  /// Salt acak 16 byte dalam base64.
  String newSalt() => base64Encode(
        Uint8List.fromList(List.generate(16, (_) => _random.nextInt(256))),
      );

  Future<String> hash(String secret, String salt) {
    final iterations = this.iterations;
    if (!useIsolate) return Future.value(_pbkdf2(secret, salt, iterations));
    return Isolate.run(() => _pbkdf2(secret, salt, iterations));
  }

  Future<bool> verify(String secret, String salt, String expectedHash) async {
    final actual = await hash(secret, salt);
    return _constantTimeEquals(actual, expectedHash);
  }

  static String _pbkdf2(String secret, String salt, int iterations) {
    final hmac = Hmac(sha256, utf8.encode(secret));
    // Satu blok (32 byte) sudah cukup: INT(1) ditambahkan ke salt.
    final first = <int>[...base64Decode(salt), 0, 0, 0, 1];
    var u = hmac.convert(first).bytes;
    final result = Uint8List.fromList(u);
    for (var i = 1; i < iterations; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < result.length; j++) {
        result[j] ^= u[j];
      }
    }
    return base64Encode(result);
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}

final pinHasherProvider = Provider<PinHasher>((ref) => const PinHasher());
