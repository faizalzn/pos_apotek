import 'dart:io';

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
import 'package:pos_apotek/features/settings/data/settings_repository.dart';
import 'package:pos_apotek/features/setup/data/setup_service.dart';

import 'helpers.dart';

void main() {
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
  });

  tearDown(() => photos.deleteSync(recursive: true));

  Future<void> tapOn(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> login(WidgetTester tester, String name, String pin) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
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
    expect(find.text('Halo, $name'), findsOneWidget);
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await db.close();
  }

  testWidgets('pemilik menambah produk + satuan, lalu menambah stok', (
    tester,
  ) async {
    await login(tester, 'Sari', '482915');

    await tapOn(tester, find.text('Produk'));
    expect(find.text('Belum ada produk'), findsOneWidget);
    await tapOn(tester, find.text('Tambah produk'));

    // Simpan kosong → validasi
    await tapOn(tester, find.text('Simpan produk'));
    expect(find.text('Nama produk wajib diisi'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('product-name')),
      'Paracetamol 500mg',
    );
    // Satuan terkecil: Tablet (bawaan), harga 500
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Harga jual *').first,
      '500',
    );
    // Tambah satuan Strip isi 10
    await tapOn(tester, find.text('Tambah kemasan (Strip, Box, ...)'));
    await tapOn(tester, find.widgetWithText(ChoiceChip, 'Strip'));
    await tester.enterText(find.widgetWithText(TextFormField, 'Isi *'), '10');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Harga jual *').last,
      '4500',
    );
    await tester.pump();
    expect(find.text('4.500'), findsOneWidget); // pemisah ribuan otomatis
    expect(find.text('Bila dijual eceran: Rp5.000'), findsOneWidget);

    // Box isi 10 Strip → tersimpan sebagai 100 Tablet
    await tapOn(tester, find.text('Tambah kemasan lebih besar'));
    await tapOn(tester, find.widgetWithText(ChoiceChip, 'Box').last);
    await tester.enterText(find.widgetWithText(TextFormField, 'Isi *').last, '10');
    await tester.pump();
    expect(find.text('= 100 Tablet'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Harga jual *').last,
      '42000',
    );
    // Peringatan stok menipis otomatis: kurang dari 1 Strip
    expect(find.text('Kosong = otomatis, diingatkan bila kurang dari 1 Strip'), findsOneWidget);

    await tapOn(tester, find.text('Simpan produk'));
    expect(find.text('Produk tersimpan'), findsOneWidget);
    await tapOn(tester, find.text('Tambah stok'));

    // Tambah stok: 3 Strip, ED Agustus 2027
    expect(find.text('Tambah Stok'), findsOneWidget);
    expect(find.text('Box (isi 100)'), findsOneWidget);
    await tapOn(tester, find.text('Strip (isi 10)'));
    await tester.enterText(find.byKey(const Key('stock-qty')), '3');
    await tester.pump();
    expect(find.text('= 30 Tablet'), findsOneWidget);

    await tapOn(tester, find.text('Simpan stok'));
    expect(find.text('Pilih bulan & tahun kedaluwarsa'), findsOneWidget);

    await tapOn(tester, find.byKey(const Key('pick-expiry')));
    final year = DateTime.now().year + 1;
    await tapOn(tester, find.text('Agu'));
    await tapOn(tester, find.text('Agustus $year'));
    await tapOn(tester, find.text('Simpan stok'));

    // Kembali ke daftar produk
    expect(find.text('Paracetamol 500mg'), findsOneWidget);
    expect(find.text('Stok: 3 Strip'), findsOneWidget);
    expect(find.text('Rp500'), findsOneWidget);

    // Pencarian
    await tester.enterText(find.byKey(const Key('product-search')), 'amoxi');
    await tester.pumpAndSettle();
    expect(find.text('Tidak ada produk yang cocok'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('product-search')), 'parace');
    await tester.pumpAndSettle();
    expect(find.text('Paracetamol 500mg'), findsOneWidget);

    // Detail menampilkan batch & ED
    await tapOn(tester, find.text('Paracetamol 500mg'));
    expect(find.text('ED Agu $year'), findsOneWidget);
    expect(find.text('30 Tablet'), findsOneWidget);

    await finish(tester);
  });

  testWidgets('kasir melihat produk tetapi tidak bisa menambah/mengubah', (
    tester,
  ) async {
    await login(tester, 'Dewi', '739164');
    await tapOn(tester, find.text('Produk'));
    expect(find.text('Tambah produk'), findsNothing);
    expect(find.text('Diarsipkan'), findsNothing);
    await finish(tester);
  });

  testWidgets('menu Stok & ED menampilkan jumlah per peringatan', (
    tester,
  ) async {
    await login(tester, 'Sari', '482915');
    await tapOn(tester, find.text('Stok & ED'));
    expect(find.text('Stok & Kedaluwarsa'), findsOneWidget);
    expect(find.text('Kedaluwarsa'), findsOneWidget);
    expect(find.text('Hampir ED'), findsOneWidget);
    expect(find.text('Stok menipis'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('beranda memperingatkan stok menipis; ubah produk menjaga isi kemasan', (
    tester,
  ) async {
    final repo = ProductRepository(db, clock.call);
    final created = await repo.create(
      const ProductInput(
        name: 'Paracetamol',
        drugClass: DrugClass.bebas,
        units: [
          UnitInput(name: 'Tablet', multiplier: 1, sellPrice: 500),
          UnitInput(name: 'Strip', multiplier: 10, sellPrice: 4500),
          UnitInput(name: 'Box', multiplier: 100, sellPrice: 42000),
        ],
      ),
    );
    final p = (await repo.getOne(created.id))!;
    await repo.receiveStock(
      productId: p.product.id,
      unit: p.baseUnit,
      quantity: 5,
      expiryDate: endOfMonth(2028, 1),
      costPerSelectedUnit: 300,
    );

    await login(tester, 'Sari', '482915');
    expect(find.text('Obat perlu diperhatikan'), findsOneWidget);
    expect(find.text('1 stok menipis'), findsOneWidget);

    await tapOn(tester, find.byKey(const Key('stock-alert')));
    expect(find.text('Stok & Kedaluwarsa'), findsOneWidget);
    await tapOn(tester, find.text('Stok menipis'));
    await tapOn(tester, find.text('Paracetamol'));
    expect(find.text('Diingatkan bila kurang dari 1 Strip (otomatis)'), findsOneWidget);

    // Ubah: Box tampil "isi 10 Strip", bukan 100
    await tapOn(tester, find.byTooltip('Ubah'));
    final isi = find.widgetWithText(TextFormField, 'Isi *');
    expect(tester.widget<TextFormField>(isi.at(0)).controller!.text, '10');
    expect(tester.widget<TextFormField>(isi.at(1)).controller!.text, '10');
    expect(find.text('= 100 Tablet'), findsOneWidget);

    // Batas menipis: 2 Strip → disimpan 20 Tablet
    await tester.enterText(find.byKey(const Key('min-stock')), '2');
    await tapOn(tester, find.widgetWithText(DropdownButtonFormField<int>, 'Tablet'));
    await tapOn(tester, find.text('Strip').last);
    await tapOn(tester, find.text('Simpan perubahan'));
    final saved = (await repo.getOne(created.id))!;
    expect(saved.units.map((u) => u.multiplier), [1, 10, 100]);
    expect(saved.product.minStock, 20);
    await finish(tester);
  });
}
