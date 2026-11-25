import 'package:drift/drift.dart' show Value;
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
import 'package:pos_apotek/features/shift/data/shift_receipt.dart';
import 'package:pos_apotek/features/shift/data/shift_service.dart';

import '../helpers.dart';

void main() {
  late AppDatabase db;
  late FakeClock clock;
  late ShiftService shifts;
  late SaleService sales;
  late ProductRepository products;
  late ProviderContainer container;
  late AppUser owner;
  late AppUser cashier;
  late ProductSummary para;

  setUp(() async {
    db = memoryDatabase();
    clock = FakeClock(DateTime(2026, 11, 25, 7));
    shifts = ShiftService(db, clock.call);
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
      const ProductInput(
        name: 'Paracetamol',
        drugClass: DrugClass.bebas,
        units: [UnitInput(name: 'Tablet', multiplier: 1, sellPrice: 1000)],
      ),
    );
    final s = (await products.getOne(p.id))!;
    await products.receiveStock(
      productId: p.id,
      unit: s.baseUnit,
      quantity: 100,
      expiryDate: endOfMonth(2028, 1),
    );
    para = (await products.getOne(p.id))!;
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<Sale> sell(int qty, PaymentMethod method, AppUser by) async {
    final cart = container.read(cartProvider.notifier)..clear();
    cart.add(para, para.baseUnit, quantity: qty);
    final sale = await sales.complete(
      cart: container.read(cartProvider),
      method: method,
      amountPaid: qty * 1000,
      cashier: by,
    );
    para = (await products.getOne(para.product.id))!;
    return sale;
  }

  test(
    'alur shift: buka → jual → kas keluar/masuk → tutup dengan selisih',
    () async {
      final shift = await shifts.open(by: cashier, openingCash: 100000);
      expect((await shifts.getOpen())!.id, shift.id);

      // Tidak boleh dua shift terbuka sekaligus
      expect(
        () => shifts.open(by: owner, openingCash: 0),
        throwsA(isA<UserRuleException>()),
      );

      clock.advance(const Duration(hours: 1));
      await sell(5, PaymentMethod.cash, cashier); // 5.000
      await sell(3, PaymentMethod.qris, cashier); // 3.000 (tidak masuk laci)
      final batal = await sell(
        2,
        PaymentMethod.cash,
        cashier,
      ); // 2.000, lalu dibatalkan
      await sales.voidSale(saleId: batal.id, reason: 'salah', by: owner);

      await shifts.addCashEntry(
        type: CashEntryType.cashOut,
        amount: 15000,
        note: 'Beli galon',
        by: cashier,
      );
      await shifts.addCashEntry(
        type: CashEntryType.cashIn,
        amount: 50000,
        note: 'Tambah uang kecil dari Pemilik',
        by: owner,
      );

      var s = await shifts.summary(shift.id);
      expect(s.saleCount, 2);
      expect(s.cashSales, 5000);
      expect(s.qrisSales, 3000);
      expect(s.voidCount, 1);
      expect(s.cashIn, 50000);
      expect(s.cashOut, 15000);
      expect(s.expectedCash, 100000 + 5000 + 50000 - 15000); // 140.000
      expect(s.entries.map((e) => e.userName), ['Dewi', 'Sari']);

      // Selisih tanpa keterangan ditolak
      await expectLater(
        shifts.close(shiftId: shift.id, countedCash: 139000, by: cashier),
        throwsA(isA<UserRuleException>()),
      );
      clock.advance(const Duration(hours: 7));
      s = await shifts.close(
        shiftId: shift.id,
        countedCash: 139000,
        by: cashier,
        note: 'Kurang kembalian',
      );
      expect(s.isOpen, isFalse);
      expect(s.expectedCash, 140000);
      expect(s.difference, -1000);
      expect(s.closedByName, 'Dewi');
      expect(await shifts.lastCountedCash(), 139000);
      expect(await shifts.getOpen(), isNull);

      // Uang seharusnya tersimpan: transaksi berikutnya tidak mengubahnya.
      await shifts.open(by: owner, openingCash: 139000);
      await sell(1, PaymentMethod.cash, owner);
      expect((await shifts.summary(shift.id)).expectedCash, 140000);
    },
  );

  test(
    'pembatalan transaksi shift sebelumnya mengurangi laci shift sekarang',
    () async {
      final pagi = await shifts.open(by: cashier, openingCash: 50000);
      final sale = await sell(4, PaymentMethod.cash, cashier); // 4.000
      await shifts.close(shiftId: pagi.id, countedCash: 54000, by: cashier);

      clock.advance(const Duration(hours: 8));
      final sore = await shifts.open(by: owner, openingCash: 54000);
      await sales.voidSale(
        saleId: sale.id,
        reason: 'obat dikembalikan',
        by: owner,
      );

      final s = await shifts.summary(sore.id);
      expect(s.refunds, 4000);
      expect(s.expectedCash, 50000);
      // Shift pagi tidak berubah
      expect((await shifts.summary(pagi.id)).difference, 0);
    },
  );

  test('kas keluar tidak boleh melebihi isi laci; keterangan wajib', () async {
    await shifts.open(by: cashier, openingCash: 10000);
    expect(
      () => shifts.addCashEntry(
        type: CashEntryType.cashOut,
        amount: 20000,
        note: 'x',
        by: cashier,
      ),
      throwsA(isA<UserRuleException>()),
    );
    expect(
      () => shifts.addCashEntry(
        type: CashEntryType.cashIn,
        amount: 1000,
        note: ' ',
        by: cashier,
      ),
      throwsA(isA<UserRuleException>()),
    );
  });

  test('daftar shift per rentang tanggal', () async {
    final a = await shifts.open(by: cashier, openingCash: 0);
    await shifts.close(shiftId: a.id, countedCash: 0, by: cashier);
    clock.advance(const Duration(days: 1));
    await shifts.open(by: owner, openingCash: 0);
    final today = await shifts.inRange(
      DateTime(2026, 11, 26),
      DateTime(2026, 11, 27),
    );
    expect(today.map((s) => s.openedByName), ['Sari']);
    final both = await shifts.inRange(
      DateTime(2026, 11, 25),
      DateTime(2026, 11, 27),
    );
    expect(both, hasLength(2));
  });

  test('transaksi lama (tanpa shift) yang dibatalkan dihitung sebagai pengembalian', () async {
    final shift = await shifts.open(by: owner, openingCash: 20000);
    final sale = await sell(3, PaymentMethod.cash, owner);
    // Tiru transaksi dari sebelum ada fitur shift.
    await (db.update(db.sales)..where((s) => s.id.equals(sale.id))).write(
      const SalesCompanion(shiftId: Value(null)),
    );
    clock.advance(const Duration(minutes: 5));
    await sales.voidSale(saleId: sale.id, reason: 'uji', by: owner);
    final s = await shifts.summary(shift.id);
    expect(s.cashSales, 0);
    expect(s.refunds, 3000);
  });

  test('ringkasan shift untuk printer muat di kertas', () async {
    final shift = await shifts.open(by: cashier, openingCash: 50000);
    await sell(2, PaymentMethod.cash, cashier);
    await shifts.addCashEntry(
      type: CashEntryType.cashOut,
      amount: 5000,
      note: 'Bayar tukang parkir dan beli air minum galon',
      by: cashier,
    );
    final s = await shifts.close(
      shiftId: shift.id,
      countedCash: 46000,
      by: owner,
      note: 'Uang receh kurang',
    );
    for (final cols in [32, 48]) {
      final lines = buildShiftReceipt(
        s,
        storeName: 'Apotek Sehat',
        columns: cols,
      );
      for (final l in lines) {
        expect(l.text.length, lessThanOrEqualTo(cols), reason: l.text);
      }
      final text = lines.map((l) => l.text).join('\n');
      expect(text, contains('RINGKASAN SHIFT'));
      expect(text, contains('Ditutup oleh'));
      expect(text, contains('-1.000'));
    }
  });
}
