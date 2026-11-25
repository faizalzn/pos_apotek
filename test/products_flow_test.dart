import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pos_apotek/app.dart';
import 'package:pos_apotek/core/clock.dart';
import 'package:pos_apotek/core/database/app_database.dart';
import 'package:pos_apotek/core/security/pin_hasher.dart';
import 'package:pos_apotek/features/auth/data/recovery_code_service.dart';
import 'package:pos_apotek/features/auth/data/user_repository.dart';
import 'package:pos_apotek/features/products/data/photo_store.dart';
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
    await tapOn(tester, find.text('Tambah satuan kemasan (Strip, Box, ...)'));
    await tapOn(tester, find.widgetWithText(ChoiceChip, 'Strip'));
    await tester.enterText(find.widgetWithText(TextFormField, 'Isi *'), '10');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Harga jual *').last,
      '4500',
    );
    expect(find.text('4.500'), findsOneWidget); // pemisah ribuan otomatis

    await tapOn(tester, find.text('Simpan produk'));
    expect(find.text('Produk tersimpan'), findsOneWidget);
    await tapOn(tester, find.text('Tambah stok'));

    // Tambah stok: 3 Strip, ED Agustus 2027
    expect(find.text('Tambah Stok'), findsOneWidget);
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
}
