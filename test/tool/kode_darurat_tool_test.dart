import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_apotek/core/security/rescue_code.dart';

/// Menjalankan `tool/kode_darurat.dart` sungguhan, seperti yang dilakukan
/// developer di laptop.
void main() {
  late Directory temp;
  late String keyPath;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('kode_darurat_');
    keyPath = '${temp.path}/kunci.txt';
  });

  tearDown(() => temp.deleteSync(recursive: true));

  Future<ProcessResult> run(List<String> args) => Process.run(
        'dart',
        ['run', 'tool/kode_darurat.dart', ...args, '--kunci', keyPath],
      );

  test('siapkan → buat balasan → diterima aplikasi', () async {
    final setup = await run(['siapkan']);
    expect(setup.exitCode, 0, reason: '${setup.stderr}');
    final publicKey = RegExp(r'"RESCUE_PUBLIC_KEY": "([^"]+)"')
        .firstMatch(setup.stdout as String)!
        .group(1)!;

    // Tidak menimpa kunci yang sudah ada.
    final again = await run(['siapkan']);
    expect(again.exitCode, 1);

    final reply = await run(['7K3M-Q9TX']);
    expect(reply.exitCode, 0, reason: '${reply.stderr}');

    // Seluruh keluaran alat ditempel apa adanya ke aplikasi.
    expect(
      await RescueCode.verify(
        challenge: '7K3M-Q9TX',
        reply: reply.stdout as String,
        publicKey: publicKey,
      ),
      isTrue,
    );
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('kode tantangan yang salah ketik ditolak dengan pesan jelas', () async {
    await run(['siapkan']);
    final result = await run(['7K3M-Q9']);
    expect(result.exitCode, 1);
    expect(result.stderr, contains('tidak dikenali'));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
