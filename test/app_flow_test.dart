import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pos_apotek/app.dart';
import 'package:pos_apotek/core/database/app_database.dart';
import 'package:pos_apotek/core/security/pin_hasher.dart';

import 'helpers.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = memoryDatabase());

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          pinHasherProvider.overrideWithValue(fastHasher),
        ],
        child: const PosApotekApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tearDownApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await db.close();
  }

  /// Gulir ke widget dulu (bisa berada di bawah layar), lalu ketuk.
  Future<void> tapOn(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> typePin(WidgetTester tester, String pin) async {
    for (final digit in pin.split('')) {
      await tester.tap(find.text(digit));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets('setup awal → beranda → keluar → login dengan PIN', (
    tester,
  ) async {
    await pumpApp(tester);

    // Langkah 0: sambutan
    expect(find.text('Selamat datang di POS Apotek'), findsOneWidget);
    await tapOn(tester, find.text('Mulai'));

    // Langkah 1: data apotek — nama wajib diisi
    await tapOn(tester, find.text('Lanjut'));
    expect(find.text('Nama apotek wajib diisi'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('store-name')), 'Apotek Uji');
    await tapOn(tester, find.text('Lanjut'));

    // Langkah 2: akun pemilik
    await tester.enterText(find.byKey(const Key('owner-name')), 'Sari');
    await tapOn(tester, find.text('Lanjut'));
    expect(find.text('Buat PIN untuk Sari'), findsOneWidget);

    // PIN lemah ditolak
    await typePin(tester, '123456');
    expect(find.textContaining('mudah ditebak'), findsOneWidget);

    // PIN konfirmasi tidak sama
    await typePin(tester, '482915');
    expect(find.text('Ulangi PIN'), findsOneWidget);
    await typePin(tester, '482916');
    expect(find.text('PIN tidak sama. Silakan buat ulang.'), findsOneWidget);

    await typePin(tester, '482915');
    await typePin(tester, '482915');

    // Langkah 3: kode pemulihan — tombol aktif setelah dicentang
    expect(find.text('Kode Pemulihan'), findsOneWidget);
    final done = find.widgetWithText(FilledButton, 'Selesai, masuk ke aplikasi');
    expect(tester.widget<FilledButton>(done).onPressed, isNull);
    await tapOn(tester, find.text('Saya sudah mencatat kode ini'));
    await tapOn(tester, done);

    // Beranda
    expect(find.text('Halo, Sari'), findsOneWidget);
    expect(find.text('Apotek Uji'), findsOneWidget);
    expect(find.text('Laporan'), findsOneWidget); // menu khusus pemilik

    // Keluar → login (hanya satu pengguna, langsung ke PIN)
    await tester.tap(find.byTooltip('Keluar'));
    await tester.pumpAndSettle();
    expect(find.text('Masukkan PIN Anda'), findsOneWidget);

    await typePin(tester, '000001');
    expect(find.text('PIN salah. Sisa percobaan: 4'), findsOneWidget);

    await typePin(tester, '482915');
    expect(find.text('Halo, Sari'), findsOneWidget);

    await tearDownApp(tester);
  });

  testWidgets('pemilik menambah kasir; kasir tidak melihat menu Laporan', (
    tester,
  ) async {
    await pumpApp(tester);

    // Setup singkat
    await tapOn(tester, find.text('Mulai'));
    await tester.enterText(find.byKey(const Key('store-name')), 'Apotek Uji');
    await tapOn(tester, find.text('Lanjut'));
    await tester.enterText(find.byKey(const Key('owner-name')), 'Sari');
    await tapOn(tester, find.text('Lanjut'));
    await typePin(tester, '482915');
    await typePin(tester, '482915');
    await tapOn(tester, find.text('Saya sudah mencatat kode ini'));
    await tapOn(tester, find.text('Selesai, masuk ke aplikasi'));

    // Pengaturan → Pengguna → Tambah
    await tester.tap(find.text('Pengaturan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pengguna'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tambah pengguna'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Dewi');
    await tapOn(tester, find.text('Lanjut ke PIN'));
    await typePin(tester, '739164');
    await typePin(tester, '739164');
    expect(find.text('Dewi'), findsOneWidget);
    expect(find.text('Sari (Anda)'), findsOneWidget);

    // Kembali ke beranda, lalu keluar
    await tapOn(tester, find.byType(BackButton));
    await tapOn(tester, find.byType(BackButton));
    await tester.tap(find.byTooltip('Keluar'));
    await tester.pumpAndSettle();

    // Dua pengguna → pilih nama dulu
    expect(find.text('Siapa yang bertugas?'), findsOneWidget);
    await tester.tap(find.text('Dewi'));
    await tester.pumpAndSettle();
    await typePin(tester, '739164');

    expect(find.text('Halo, Dewi'), findsOneWidget);
    expect(find.text('Laporan'), findsNothing);

    await tearDownApp(tester);
  });
}
