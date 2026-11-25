import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_apotek/core/clock.dart';
import 'package:pos_apotek/core/database/app_database.dart';
import 'package:pos_apotek/core/format.dart';
import 'package:pos_apotek/features/auth/data/user_repository.dart';
import 'package:pos_apotek/features/products/data/product_models.dart';
import 'package:pos_apotek/features/products/data/product_repository.dart';
import 'package:pos_apotek/features/sales/application/cart_controller.dart';
import 'package:pos_apotek/features/sales/data/sale_service.dart';

import '../helpers.dart';

void main() {
  late AppDatabase db;
  late FakeClock clock;
  late ProductRepository products;
  late SaleService sales;
  late ProviderContainer container;
  late AppUser owner;
  late AppUser cashier;
  late ProductSummary para;

  CartController cart() => container.read(cartProvider.notifier);
  Cart cartState() => container.read(cartProvider);
  ProductUnit unit(ProductSummary p, String name) =>
      p.units.firstWhere((u) => u.name == name);

  setUp(() async {
    db = memoryDatabase();
    clock = FakeClock(DateTime(2026, 11, 25, 9));
    products = ProductRepository(db, clock.call);
    sales = SaleService(db, products, clock.call);
    container = ProviderContainer(
      overrides: [clockProvider.overrideWithValue(clock.call)],
    );
    final users = UserRepository(db, fastHasher, clock.call);
    owner = await users.create(
      name: 'Sari',
      role: UserRole.owner,
      pin: '482915',
    );
    cashier = await users.create(
      name: 'Dewi',
      role: UserRole.cashier,
      pin: '739164',
    );

    final p = await products.create(
      ProductInput(
        name: 'Paracetamol',
        drugClass: DrugClass.bebas,
        units: [
          const UnitInput(name: 'Tablet', multiplier: 1, sellPrice: 500),
          const UnitInput(name: 'Strip', multiplier: 10, sellPrice: 4500),
        ],
      ),
    );
    var s = (await products.getOne(p.id))!;
    // 2 batch: ED dekat (harga beli 200/tablet) & ED jauh (300/tablet)
    await products.receiveStock(
      productId: p.id,
      unit: unit(s, 'Strip'),
      quantity: 1,
      expiryDate: endOfMonth(2027, 3),
      batchNumber: 'DEKAT',
      costPerSelectedUnit: 2000,
    );
    await products.receiveStock(
      productId: p.id,
      unit: unit(s, 'Strip'),
      quantity: 2,
      expiryDate: endOfMonth(2028, 3),
      batchNumber: 'JAUH',
      costPerSelectedUnit: 3000,
    );
    s = (await products.getOne(p.id))!;
    para = s;
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  group('keranjang', () {
    test('menambah satuan yang sama menggabungkan baris', () {
      cart().add(para, unit(para, 'Strip'));
      cart().add(para, unit(para, 'Strip'));
      cart().add(para, unit(para, 'Tablet'), quantity: 3);
      expect(cartState().lines, hasLength(2));
      expect(cartState().lines.first.quantity, 2);
      expect(cartState().subtotal, 2 * 4500 + 3 * 500);
      expect(cartState().itemCount, 5);
    });

    test('tidak bisa melebihi stok layak jual (30 tablet)', () {
      expect(
        cart().add(para, unit(para, 'Strip'), quantity: 3),
        isA<CartChangeOk>(),
      );
      final result = cart().add(para, unit(para, 'Tablet'));
      expect(result, isA<CartChangeNoStock>());
      expect((result as CartChangeNoStock).availableBase, 0);

      expect(cart().setQuantity(0, 4), isA<CartChangeNoStock>());
      expect(cartState().lines.single.quantity, 3);
    });

    test('jumlah 0 menghapus baris; diskon disesuaikan otomatis', () {
      cart().add(para, unit(para, 'Strip'), quantity: 2);
      cart().updatePricing(0, unitPrice: 4500, discount: 99999);
      expect(cartState().lines.single.discount, 9000); // maks. = harga baris
      cart().setQuantity(0, 1);
      expect(cartState().lines.single.discount, 4500);
      cart().setDiscount(100000);
      expect(cartState().discount, 0); // tidak ada sisa setelah diskon barang
      cart().setQuantity(0, 0);
      expect(cartState().isEmpty, isTrue);
    });

    test(
      'total = subtotal − diskon barang − diskon total, tanpa pembulatan',
      () {
        cart().add(para, unit(para, 'Tablet'), quantity: 7); // 3.500
        cart().updatePricing(0, unitPrice: 485, discount: 45); // 3.395 − 45
        cart().setDiscount(1);
        expect(cartState().subtotal, 3395);
        expect(cartState().itemDiscount, 45);
        expect(cartState().total, 3349);
      },
    );
  });

  group('transaksi', () {
    test(
      'tunai: stok berkurang FEFO, kembalian & harga beli tercatat',
      () async {
        cart().add(para, unit(para, 'Strip'), quantity: 1);
        cart().add(para, unit(para, 'Tablet'), quantity: 5);
        final sale = await sales.complete(
          cart: cartState(),
          method: PaymentMethod.cash,
          amountPaid: 10000,
          cashier: cashier,
        );

        expect(sale.number, '261125-0001');
        expect(sale.total, 7000);
        expect(sale.change, 3000);
        // 10 tablet dari batch DEKAT (200) + 5 dari JAUH (300)
        expect(sale.costTotal, 10 * 200 + 5 * 300);

        final after = (await products.getOne(para.product.id))!;
        expect(after.stock, 15);
        expect(after.batches.map((b) => b.batchNumber), ['JAUH']);

        final detail = await sales.watchDetail(sale.id).first;
        expect(detail!.items.map((i) => '${i.quantity} ${i.unitName}'), [
          '1 Strip',
          '5 Tablet',
        ]);
        expect(detail.cashierName, 'Dewi');
      },
    );

    test('nomor transaksi berurutan per hari', () async {
      Future<String> sell() async {
        cart().add(para, unit(para, 'Tablet'));
        final s = await sales.complete(
          cart: cartState(),
          method: PaymentMethod.qris,
          amountPaid: 0,
          cashier: owner,
        );
        cart().clear();
        return s.number;
      }

      expect(await sell(), '261125-0001');
      expect(await sell(), '261125-0002');
      clock.advance(const Duration(days: 1));
      expect(await sell(), '261126-0001');
    });

    test('QRIS: dibayar persis sebesar total', () async {
      cart().add(para, unit(para, 'Tablet'), quantity: 3);
      final sale = await sales.complete(
        cart: cartState(),
        method: PaymentMethod.qris,
        amountPaid: 999999,
        cashier: cashier,
      );
      expect(sale.amountPaid, 1500);
      expect(sale.change, 0);
    });

    test('uang tunai kurang ditolak', () async {
      cart().add(para, unit(para, 'Strip'));
      expect(
        () => sales.complete(
          cart: cartState(),
          method: PaymentMethod.cash,
          amountPaid: 4000,
          cashier: cashier,
        ),
        throwsA(isA<UserRuleException>()),
      );
    });

    test('kasir tidak boleh mengubah harga / memberi diskon', () async {
      cart().add(para, unit(para, 'Strip'));
      cart().setDiscount(500);
      await expectLater(
        sales.complete(
          cart: cartState(),
          method: PaymentMethod.cash,
          amountPaid: 4500,
          cashier: cashier,
        ),
        throwsA(isA<UserRuleException>()),
      );
      // Pemilik boleh
      final sale = await sales.complete(
        cart: cartState(),
        method: PaymentMethod.cash,
        amountPaid: 4000,
        cashier: owner,
      );
      expect(sale.total, 4000);
      expect(sale.discount, 500);
    });

    test('stok habis di tengah transaksi → tidak ada yang tersimpan', () async {
      cart().add(para, unit(para, 'Strip'), quantity: 2);
      // Stok berkurang dari tempat lain setelah barang masuk keranjang.
      await products.consumeFefo(productId: para.product.id, quantity: 15);

      await expectLater(
        sales.complete(
          cart: cartState(),
          method: PaymentMethod.cash,
          amountPaid: 9000,
          cashier: cashier,
        ),
        throwsA(
          isA<UserRuleException>().having(
            (e) => e.message,
            'message',
            contains('Tersisa 15 Tablet'),
          ),
        ),
      );
      expect((await products.getOne(para.product.id))!.stock, 15);
      expect(await sales.watchDay(clock()).first, isEmpty);
    });

    test(
      'batal transaksi: stok kembali ke batch asal (hanya Pemilik)',
      () async {
        cart().add(para, unit(para, 'Strip'), quantity: 2);
        final sale = await sales.complete(
          cart: cartState(),
          method: PaymentMethod.cash,
          amountPaid: 9000,
          cashier: cashier,
        );
        expect((await products.getOne(para.product.id))!.stock, 10);

        expect(
          () => sales.voidSale(saleId: sale.id, reason: 'salah', by: cashier),
          throwsA(isA<UserRuleException>()),
        );
        await sales.voidSale(saleId: sale.id, reason: 'Salah input', by: owner);

        final restored = (await products.getOne(para.product.id))!;
        expect(restored.stock, 30);
        expect(restored.batches.map((b) => '${b.batchNumber}:${b.quantity}'), [
          'DEKAT:10',
          'JAUH:20',
        ]);
        final detail = (await sales.watchDetail(sale.id).first)!;
        expect(detail.sale.status, SaleStatus.voided);
        expect(detail.voidedByName, 'Sari');
        expect(
          () => sales.voidSale(saleId: sale.id, reason: 'lagi', by: owner),
          throwsA(isA<UserRuleException>()),
        );
      },
    );

    test('riwayat per hari hanya menampilkan hari tersebut', () async {
      cart().add(para, unit(para, 'Tablet'));
      await sales.complete(
        cart: cartState(),
        method: PaymentMethod.cash,
        amountPaid: 500,
        cashier: cashier,
      );
      expect(await sales.watchDay(DateTime(2026, 11, 25)).first, hasLength(1));
      expect(await sales.watchDay(DateTime(2026, 11, 24)).first, isEmpty);
      expect(await sales.watchDay(DateTime(2026, 11, 26)).first, isEmpty);
    });
  });

  test(
    'peringatan ED mengikuti pengaturan produk atau pengaturan umum',
    () async {
      final now = DateTime(2026, 11, 25);
      final ed = DateTime(2027, 3, 31); // ±4 bulan lagi
      expect(expiryStatusOf(ed, now), ExpiryStatus.ok); // bawaan 3 bulan
      expect(expiryStatusOf(ed, now, windowDays: 180), ExpiryStatus.soon);

      // Pengaturan umum 6 bulan → batch DEKAT (Mar 2027) jadi "hampir ED"
      await db
          .into(db.appSettings)
          .insert(
            AppSettingsCompanion.insert(
              key: nearExpirySettingKey,
              value: '180',
              updatedAt: now,
            ),
          );
      var s = (await products.getOne(para.product.id))!;
      expect(s.nearExpiryDays, 180);
      expect(s.expiryStatus(now), ExpiryStatus.soon);

      // Produk ini diatur khusus 1 bulan → tidak lagi "hampir ED"
      await products.update(
        para.product.id,
        ProductInput(
          name: 'Paracetamol',
          drugClass: DrugClass.bebas,
          nearExpiryDays: 30,
          units: [
            for (final u in s.units)
              UnitInput(
                id: u.id,
                name: u.name,
                multiplier: u.multiplier,
                sellPrice: u.sellPrice,
              ),
          ],
        ),
      );
      s = (await products.getOne(para.product.id))!;
      expect(s.nearExpiryDays, 30);
      expect(s.expiryStatus(now), ExpiryStatus.ok);
    },
  );
}
