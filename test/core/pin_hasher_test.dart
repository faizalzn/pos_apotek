import 'package:flutter_test/flutter_test.dart';
import 'package:pos_apotek/core/security/pin_hasher.dart';

void main() {
  test('cocok dengan PBKDF2-HMAC-SHA256 referensi (Python hashlib)', () async {
    // hashlib.pbkdf2_hmac('sha256', b'123987', b'0123456789abcdef', 1000)
    const hasher = PinHasher(iterations: 1000, useIsolate: false);
    final hash = await hasher.hash('123987', 'MDEyMzQ1Njc4OWFiY2RlZg==');
    expect(hash, 'dDi4d+AF7V5i1rRwYLAGjItQTloSvmcIKBcg26/D/xA=');
  });

  test('verify menerima PIN benar dan menolak PIN salah', () async {
    const hasher = PinHasher(iterations: 10, useIsolate: false);
    final salt = hasher.newSalt();
    final hash = await hasher.hash('482915', salt);
    expect(await hasher.verify('482915', salt, hash), isTrue);
    expect(await hasher.verify('482916', salt, hash), isFalse);
  });

  test('salt berbeda menghasilkan hash berbeda', () async {
    const hasher = PinHasher(iterations: 10, useIsolate: false);
    final a = await hasher.hash('482915', hasher.newSalt());
    final b = await hasher.hash('482915', hasher.newSalt());
    expect(a, isNot(b));
  });

  test('berjalan di isolate', () async {
    const hasher = PinHasher(iterations: 1000);
    final hash = await hasher.hash('123987', 'MDEyMzQ1Njc4OWFiY2RlZg==');
    expect(hash, 'dDi4d+AF7V5i1rRwYLAGjItQTloSvmcIKBcg26/D/xA=');
  });
}
