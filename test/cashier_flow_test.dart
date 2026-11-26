import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:pos_apotek/app.dart';
import 'package:pos_apotek/core/clock.dart';
import 'package:pos_apotek/core/database/app_database.dart';
import 'package:pos_apotek/core/format.dart';
import 'package:pos_apotek/core/security/pin_hasher.dart';
import 'package:pos_apotek/features/auth/data/recovery_code_service.dart';
import 'package:pos_apotek/features/auth/data/user_repository.dart';
import 'package:pos_apotek/features/products/data/photo_store.dart';
import 'package:pos_apotek/features/products/data/product_models.dart';
import 'package:pos_apotek/features/products/data/product_repository.dart';
import 'package:pos_apotek/features/qris/data/qris.dart';
import 'package:pos_apotek/features/qris/data/qris_repository.dart';
import 'package:pos_apotek/features/sales/presentation/payment_screen.dart';
import 'package:pos_apotek/features/settings/data/settings_repository.dart';
import 'package:pos_apotek/features/setup/data/setup_service.dart';

import 'features/qris_test.dart' show sampleStatic;
import 'helpers.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late Directory photos;
  final clock = FakeClock(DateTime(2026, 11, 25, 9));

  setUp(() async {
    db = memoryDatabase();
    photos = Directory.systemTemp.createTempSync('photos_');
    final settings = SettingsRepository(db, clock.call);
    final users = UserRepository(db, fastHasher, clock.call);
    await SetupService(
      db,
      settings,
      users,
      RecoveryCodeService(settings, users, fastHasher),
    ).complete(
      store: const StoreProfile(name: 'Apotek Uji'),
      ownerName: 'Sari',
      ownerPin: '482915',
    );
    await users.create(name: 'Dewi', role: UserRole.cashier, pin: '739164');

    final products = ProductRepository(db, clock.call);
    Future<void> add(
      String name,
      DrugClass c,
      List<UnitInput> units,
      int qty,
    ) async {
      final p = await products.create(
        ProductInput(name: name, drugClass: c, units: units),
      );
      final s = (await products.getOne(p.id))!;
      await products.receiveStock(
        productId: p.id,
        unit: s.baseUnit,
        quantity: qty,
        expiryDate: endOfMonth(2028, 1),
      );
    }

    await add('Paracetamol', DrugClass.bebas, [
      const UnitInput(name: 'Tablet', multiplier: 1, sellPrice: 500),
      const UnitInput(
        name: 'Strip',
        multiplier: 10,
        sellPrice: 4500,
        barcode: '899100',
      ),
    ], 30);
    await add('Amoxicillin', DrugClass.keras, [
      const UnitInput(name: 'Kapsul', multiplier: 1, sellPrice: 1200),
    ], 20);
  });

  tearDown(() => photos.deleteSync(recursive: true));

  Future<void> tapOn(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> login(
    WidgetTester tester,
    String name,
    String pin, {
    Size size = const Size(1080, 2340),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = size.width > 2000 ? 2 : 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          pinHasherProvider.overrideWithValue(fastHasher),
          clockProvider.overrideWithValue(clock.call),
          photoStoreProvider.overrideWith((ref) => PhotoStore(photos)),
        ],
        child: const PosApotekApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tapOn(tester, find.text(name));
    for (final d in pin.split('')) {
      await tester.tap(find.text(d));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  /// Dari layar Kasir yang meminta "Buka shift dulu".
  Future<void> openShift(WidgetTester tester, String cash) async {
    expect(find.text('Buka shift dulu'), findsOneWidget);
    await tapOn(tester, find.byKey(const Key('open-shift')));
    await tester.enterText(find.byKey(const Key('opening-cash')), cash);
    await tapOn(tester, find.byKey(const Key('confirm-open-shift')));
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await db.close();
  }

  testWidgets(
    'kasir (HP): pilih satuan → keranjang → tunai → kembalian → riwayat',
    (tester) async {
      await login(tester, 'Dewi', '739164');
      await tapOn(tester, find.text('Kasir'));
      await openShift(tester, '100000');

      // Paracetamol punya 2 satuan → pilih Strip
      await tapOn(tester, find.text('Paracetamol'));
      await tapOn(tester, find.text('Strip'));
      expect(find.text('Paracetamol (Strip) ditambahkan'), findsOneWidget);

      // Obat keras → peringatan resep
      await tapOn(tester, find.text('Amoxicillin'));
      expect(
        find.textContaining('pastikan pelanggan membawa resep'),
        findsOneWidget,
      );

      // Bilah keranjang: 2 barang, Rp5.700
      expect(find.text('Rp5.700'), findsOneWidget);
      await tapOn(tester, find.byKey(const Key('open-cart')));
      expect(find.text('Perlu resep'), findsOneWidget);

      // Tambah Amoxicillin jadi 2 → total Rp6.900
      await tapOn(tester, find.byTooltip('Tambah').last);
      expect(
        tester.widget<Text>(find.byKey(const Key('cart-total'))).data,
        'Rp6.900',
      );
      // Kasir tidak bisa memberi diskon
      expect(find.text('Diskon total (opsional)'), findsNothing);

      await tapOn(tester, find.byKey(const Key('pay')));
      final complete = find.byKey(const Key('complete-sale'));
      expect(tester.widget<FilledButton>(complete).onPressed, isNull);

      await tester.enterText(find.byKey(const Key('cash-received')), '10000');
      await tester.pump();
      expect(find.text('10.000'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('change'))).data,
        'Rp3.100',
      );

      await tapOn(tester, complete);
      expect(find.text('Transaksi berhasil'), findsOneWidget);
      expect(find.textContaining('261125-0001'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('success-change'))).data,
        'Rp3.100',
      );

      // Struk: printer belum diatur → kasir diberi tahu, tidak macet
      expect(find.text('Printer belum diatur'), findsOneWidget);
      await tapOn(tester, find.byKey(const Key('print-receipt')));
      // Pengaturan dibaca dari stream database: majukan waktu sedikit.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      expect(find.textContaining('Minta Pemilik mengaturnya'), findsOneWidget);
      expect(find.byKey(const Key('receipt-whatsapp')), findsOneWidget);

      // Kembali ke beranda → Riwayat
      await tapOn(tester, find.text('Kembali ke beranda'));
      await tapOn(tester, find.text('Riwayat'));
      expect(
        tester.widget<Text>(find.byKey(const Key('day-total'))).data,
        'Rp6.900',
      );
      expect(find.text('1 transaksi'), findsOneWidget);

      // Stok berkurang
      final p = (await ProductRepository(
        db,
        clock.call,
      ).loadAll()).firstWhere((x) => x.product.name == 'Paracetamol');
      expect(p.stock, 20);

      await finish(tester);
    },
  );

  testWidgets(
    'kasir (tablet): keranjang di samping, scanner keyboard + Enter',
    (tester) async {
      await login(tester, 'Dewi', '739164', size: const Size(2560, 1600));
      await tapOn(tester, find.text('Kasir'));
      await openShift(tester, '0');
      expect(find.text('Keranjang kosong'), findsOneWidget);

      // Scanner USB/Bluetooth mengetik barcode lalu Enter
      await tester.enterText(find.byKey(const Key('cashier-search')), '899100');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(
        tester.widget<Text>(find.byKey(const Key('cart-total'))).data,
        'Rp4.500',
      );
      expect(
        find.byKey(const Key('open-cart')),
        findsNothing,
      ); // tidak perlu di tablet
      await finish(tester);
    },
  );

  testWidgets('pemilik: QRIS + diskon total + batalkan transaksi', (
    tester,
  ) async {
    await login(tester, 'Sari', '482915');
    await tapOn(tester, find.text('Kasir'));
    await openShift(tester, '50000');
    await tapOn(tester, find.text('Amoxicillin'));
    await tapOn(tester, find.byKey(const Key('open-cart')));

    await tapOn(tester, find.text('Diskon total (opsional)'));
    await tapOn(tester, find.text('Persen'));
    await tester.enterText(find.byType(TextField).last, '10');
    await tester.pump();
    await tapOn(tester, find.text('Simpan'));
    expect(
      tester.widget<Text>(find.byKey(const Key('cart-total'))).data,
      'Rp1.080',
    );

    await tapOn(tester, find.byKey(const Key('pay')));
    await tapOn(tester, find.text('QRIS'));
    await tapOn(tester, find.text('Pembayaran sudah masuk'));
    expect(find.text('Transaksi berhasil'), findsOneWidget);

    await tapOn(tester, find.text('Kembali ke beranda'));
    await tapOn(tester, find.text('Riwayat'));
    await tapOn(tester, find.textContaining('261125-0001'));
    expect(find.text('Laba kotor'), findsOneWidget);

    await tapOn(tester, find.text('Batalkan transaksi'));
    await tester.enterText(find.byType(TextField).last, 'Salah input');
    await tapOn(
      tester,
      find.widgetWithText(FilledButton, 'Batalkan transaksi'),
    );
    expect(find.text('Dibatalkan'), findsOneWidget);

    final p = (await ProductRepository(
      db,
      clock.call,
    ).loadAll()).firstWhere((x) => x.product.name == 'Amoxicillin');
    expect(p.stock, 20);
    await finish(tester);
  });

  testWidgets('shift: jual → kas keluar → tutup dengan selisih → laporan', (tester) async {
    await login(tester, 'Sari', '482915');
    expect(find.text('Shift belum dibuka'), findsOneWidget);
    await tapOn(tester, find.text('Kasir'));
    await openShift(tester, '100000');

    // Jual 1 Strip Paracetamol tunai, uang pas
    await tapOn(tester, find.text('Paracetamol'));
    await tapOn(tester, find.text('Strip'));
    await tapOn(tester, find.byKey(const Key('open-cart')));
    await tapOn(tester, find.byKey(const Key('pay')));
    await tapOn(tester, find.text('Uang pas'));
    await tapOn(tester, find.byKey(const Key('complete-sale')));
    await tapOn(tester, find.text('Kembali ke beranda'));
    expect(find.text('1 transaksi · Rp4.500'), findsOneWidget);

    // Shift → kas keluar 10.000
    await tapOn(tester, find.byKey(const Key('shift-status')));
    await tapOn(tester, find.byKey(const Key('cash-out')));
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '10000');
    await tester.enterText(fields.at(1), 'Beli galon');
    await tapOn(tester, find.text('Simpan'));
    expect(find.text('Beli galon'), findsOneWidget);
    expect(find.text('Rp94.500'), findsOneWidget); // seharusnya di laci

    // Tutup: dihitung 94.000 → kurang 500, wajib keterangan
    await tapOn(tester, find.byKey(const Key('close-shift')));
    await tester.enterText(find.byKey(const Key('counted-cash')), '94000');
    await tester.pump();
    expect(tester.widget<Text>(find.byKey(const Key('shift-diff'))).data, 'Kurang Rp500');
    // Ada selisih → tombol baru aktif setelah keterangan diisi.
    final close = find.byKey(const Key('confirm-close-shift'));
    expect(tester.widget<FilledButton>(close).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('shift-note')), 'Salah kembalian');
    await tester.pump();
    // Tutup notifikasi "Kas keluar tercatat" yang masih tampil.
    tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).clearSnackBars();
    await tester.pumpAndSettle();
    await tapOn(tester, close);
    expect(find.text('Shift berhasil ditutup'), findsOneWidget);
    await tapOn(tester, find.text('Selesai'));
    expect(find.text('Kurang Rp500'), findsOneWidget); // di riwayat shift

    // Laporan hari ini
    await tapOn(tester, find.byType(BackButton));
    await tapOn(tester, find.text('Laporan'));
    expect(tester.widget<Text>(find.descendant(
      of: find.byKey(const Key('stat-revenue')),
      matching: find.byType(Text),
    ).at(1)).data, 'Rp4.500');
    expect(find.text('Paracetamol'), findsOneWidget);
    expect(find.text('1 Strip'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('pemilik bisa mengisi token bot Telegram di aplikasi', (tester) async {
    await login(tester, 'Sari', '482915');
    await tapOn(tester, find.text('Pengaturan'));
    expect(find.text('Belum ada bot · ketuk untuk menyiapkan'), findsOneWidget);
    await tapOn(tester, find.text('Notifikasi Telegram'));
    expect(find.text('Siapkan bot Telegram (sekali saja)'), findsOneWidget);
    final save = find.byKey(const Key('telegram-save-token'));
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('telegram-token')), 'salah');
    await tester.pump();
    await tapOn(tester, save);
    expect(find.textContaining('Token tidak dikenali'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('QRIS apotek: diatur Pemilik, kasir menampilkan QR bernominal', (
    tester,
  ) async {
    await login(tester, 'Sari', '482915');
    await tapOn(tester, find.text('Pengaturan'));
    expect(
      find.text('Belum diatur · pelanggan mengetik nominal sendiri'),
      findsOneWidget,
    );
    await tapOn(tester, find.text('QRIS apotek'));
    expect(find.text('QRIS dengan nominal otomatis'), findsOneWidget);

    // (Scan stiker diwakili penyimpanan langsung; kamera tidak ada di tes.)
    await tester.runAsync(
      () => QrisRepository(db, SettingsRepository(db, clock.call)).save(sampleStatic()),
    );
    await tester.pumpAndSettle();
    expect(find.text('APOTEK CONTOH'), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget); // QR uji Rp1
    await tapOn(tester, find.byType(BackButton));
    expect(find.text('Nominal otomatis · APOTEK CONTOH'), findsOneWidget);
    await tapOn(tester, find.byType(BackButton));

    await tapOn(tester, find.text('Kasir'));
    await openShift(tester, '0');
    await tapOn(tester, find.text('Amoxicillin'));
    await tapOn(tester, find.byKey(const Key('open-cart')));
    await tapOn(tester, find.byKey(const Key('pay')));
    await tapOn(tester, find.text('QRIS'));

    expect(find.byKey(const Key('qris-dynamic')), findsOneWidget);
    expect(find.textContaining('nominal Rp1.200 sudah terisi'), findsOneWidget);

    // Layar penuh untuk pelanggan
    await tapOn(tester, find.text('Perbesar untuk pelanggan'));
    expect(find.text('Scan untuk membayar'), findsOneWidget);
    expect(find.text('Rp1.200'), findsOneWidget);
    await tapOn(tester, find.byType(BackButton));

    await tapOn(tester, find.text('Pembayaran sudah masuk'));
    expect(find.text('Transaksi berhasil'), findsOneWidget);
    await finish(tester);
  });

  test('QR yang ditampilkan berisi nominal belanja', () {
    final q = Qris.parse(sampleStatic());
    expect(Qris.parse(q.withAmount(1200)).amount, 1200);
  });

  test('pilihan uang cepat', () {
    expect(quickCashOptions(6900), [7000, 8000, 10000, 20000]);
    expect(quickCashOptions(12350), [13000, 14000, 15000, 20000]);
    expect(quickCashOptions(100000), isEmpty); // cukup "Uang pas"
  });
}
