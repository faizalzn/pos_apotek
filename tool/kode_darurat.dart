// Alat developer untuk kode darurat POS Apotek.
//
//   dart run tool/kode_darurat.dart siapkan        # sekali saja: buat kunci
//   dart run tool/kode_darurat.dart 7K3M-Q9TX      # buat kode balasan
//   dart run tool/kode_darurat.dart cek            # tampilkan kunci publik
//
// Kunci privat disimpan di LUAR repo:
//   Linux/macOS: ~/.config/pos_apotek/kunci_darurat_privat.txt
//   Windows:     %USERPROFILE%\.config\pos_apotek\kunci_darurat_privat.txt
// Lokasi lain bisa dipilih dengan `--kunci <path>` atau variabel lingkungan
// POS_APOTEK_KUNCI_DARURAT.
//
// Lihat docs/KODE_DARURAT.md.

import 'dart:io';

import 'package:pos_apotek/core/security/rescue_code.dart';

Future<void> main(List<String> arguments) async {
  final args = [...arguments];
  final keyPath = _takeOption(args, '--kunci') ??
      Platform.environment['POS_APOTEK_KUNCI_DARURAT'] ??
      _defaultKeyPath();

  if (args.isEmpty || args.first == 'bantuan' || args.first == '--help') {
    _printHelp(keyPath);
    return;
  }

  switch (args.first) {
    case 'siapkan':
      await _setup(keyPath);
    case 'cek':
      final privateKey = _readKey(keyPath);
      stdout.writeln('Kunci publik: ${await RescueCode.publicKeyOf(privateKey)}');
      stdout.writeln('Pastikan sama dengan RESCUE_PUBLIC_KEY di secrets.json.');
    default:
      await _reply(args.join(''), keyPath);
  }
}

Future<void> _setup(String keyPath) async {
  final file = File(keyPath);
  if (file.existsSync()) {
    _fail(
      'Kunci sudah ada di $keyPath\n'
      'Tidak ditimpa, agar aplikasi yang sudah terpasang tetap bisa dipulihkan.\n'
      'Jalankan "cek" untuk melihat kunci publiknya.',
    );
  }
  final keys = await RescueCode.generateKeys();
  file.parent.createSync(recursive: true);
  file.writeAsStringSync('${keys.privateKey}\n');
  if (!Platform.isWindows) {
    await Process.run('chmod', ['600', keyPath]);
  }

  stdout.writeln('''
✅ Kunci darurat berhasil dibuat.

1) Kunci PRIVAT tersimpan di:
   $keyPath
   → Simpan salinannya di password manager. JANGAN di-commit / dibagikan.
   → Jika hilang, aplikasi yang sudah terpasang tidak bisa dipulihkan.

2) Salin baris berikut ke secrets.json:
   "RESCUE_PUBLIC_KEY": "${keys.publicKey}",

3) Build ulang aplikasi dengan --dart-define-from-file=secrets.json
''');
}

Future<void> _reply(String challenge, String keyPath) async {
  if (RescueCode.normalizeChallenge(challenge) == null) {
    _fail(
      'Kode tantangan tidak dikenali: "$challenge"\n'
      'Contoh yang benar: 7K3M-Q9TX (8 huruf/angka).',
    );
  }
  final privateKey = _readKey(keyPath);
  final reply = await RescueCode.sign(
    challenge: challenge,
    privateKey: privateKey,
  );

  stdout.writeln('''
Kirim pesan di bawah ini ke Pemilik lewat WhatsApp
(salin dari baris "Kode darurat" sampai akhir):
────────────────────────────────────────
Kode darurat POS Apotek:
$reply

Salin pesan ini, buka aplikasi, lalu tekan "Tempel kode".
Berlaku 24 jam sejak kode tantangan dibuat, sekali pakai.
────────────────────────────────────────''');
}

String _readKey(String keyPath) {
  final file = File(keyPath);
  if (!file.existsSync()) {
    _fail(
      'Kunci privat tidak ditemukan di $keyPath\n'
      'Jalankan dulu: dart run tool/kode_darurat.dart siapkan\n'
      'atau pulihkan file kunci dari password manager.',
    );
  }
  return file.readAsStringSync().trim();
}

String _defaultKeyPath() {
  final home = Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      '.';
  final sep = Platform.pathSeparator;
  return [home, '.config', 'pos_apotek', 'kunci_darurat_privat.txt'].join(sep);
}

String? _takeOption(List<String> args, String name) {
  final i = args.indexOf(name);
  if (i == -1 || i + 1 >= args.length) return null;
  final value = args[i + 1];
  args.removeRange(i, i + 2);
  return value;
}

void _printHelp(String keyPath) {
  stdout.writeln('''
Kode darurat POS Apotek

  dart run tool/kode_darurat.dart siapkan      Buat kunci (sekali saja)
  dart run tool/kode_darurat.dart <KODE>       Buat kode balasan, mis. 7K3M-Q9TX
  dart run tool/kode_darurat.dart cek          Tampilkan kunci publik

Opsi:
  --kunci <path>   Lokasi file kunci privat (saat ini: $keyPath)
''');
}

Never _fail(String message) {
  stderr.writeln('❌ $message');
  exit(1);
}
