import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
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
import 'package:pos_apotek/features/sales/presentation/payment_screen.dart';
import 'package:pos_apotek/features/settings/data/settings_repository.dart';
import 'package:pos_apotek/features/setup/data/setup_service.dart';

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

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await db.close();
  }

  testWidgets(
    'kasir (HP): pilih satuan → keranjang → tunai → kembalian → riwayat',
    (tester) async {
      await login(tester, 'Dewi', '739164');
      await tapOn(tester, find.text('Kasir'));

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

  test('pilihan uang cepat', () {
    expect(quickCashOptions(6900), [7000, 8000, 10000, 20000]);
    expect(quickCashOptions(12350), [13000, 14000, 15000, 20000]);
    expect(quickCashOptions(100000), isEmpty); // cukup "Uang pas"
  });
}
