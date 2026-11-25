import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_apotek/core/clock.dart';
import 'package:pos_apotek/core/database/app_database.dart';
import 'package:pos_apotek/core/format.dart';
import 'package:pos_apotek/features/auth/data/user_repository.dart';
import 'package:pos_apotek/features/products/data/product_models.dart';
import 'package:pos_apotek/features/products/data/product_repository.dart';
import 'package:pos_apotek/features/reports/data/report_service.dart';
import 'package:pos_apotek/features/sales/application/cart_controller.dart';
import 'package:pos_apotek/features/sales/data/sale_service.dart';
import 'package:pos_apotek/features/shift/data/shift_service.dart';

import '../helpers.dart';

void main() {
  late AppDatabase db;
  late FakeClock clock;
  late ProductRepository products;
  late SaleService sales;
  late ShiftService shifts;
  late ReportService reports;
  late ProviderContainer container;
  late AppUser owner;
  late AppUser cashier;

  Future<ProductSummary> product(
    String name,
    List<UnitInput> units, {
    required double cost,
  }) async {
    final p = await products.create(
      ProductInput(name: name, drugClass: DrugClass.bebas, units: units),
    );
    final s = (await products.getOne(p.id))!;
    await products.receiveStock(
      productId: p.id,
      unit: s.baseUnit,
      quantity: 500,
      expiryDate: endOfMonth(2028, 1),
      costPerSelectedUnit: cost,
    );
    return (await products.getOne(p.id))!;
  }

  Future<Sale> sell(
    List<(ProductSummary, String, int)> lines,
    PaymentMethod method,
    AppUser by, {
    int discount = 0,
  }) async {
    final cart = container.read(cartProvider.notifier)..clear();
    for (final (p, unit, qty) in lines) {
      final fresh = (await products.getOne(p.product.id))!;
      cart.add(
        fresh,
        fresh.units.firstWhere((u) => u.name == unit),
        quantity: qty,
      );
    }
    if (discount > 0) cart.setDiscount(discount);
    final c = container.read(cartProvider);
    return sales.complete(
      cart: c,
      method: method,
      amountPaid: c.total,
      cashier: by,
    );
  }

  setUp(() async {
    db = memoryDatabase();
    clock = FakeClock(DateTime(2026, 11, 24, 8));
    products = ProductRepository(db, clock.call);
    sales = SaleService(db, products, clock.call);
    shifts = ShiftService(db, clock.call);
    reports = ReportService(db, shifts);
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
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('ringkasan, per hari, terlaris, per kasir, dan shift', () async {
    final para = await product('Paracetamol', [
      const UnitInput(name: 'Tablet', multiplier: 1, sellPrice: 500),
      const UnitInput(name: 'Strip', multiplier: 10, sellPrice: 4500),
    ], cost: 300);
    final amox = await product('Amoxicillin', [
      const UnitInput(name: 'Kapsul', multiplier: 1, sellPrice: 1500),
    ], cost: 1000);

    // Senin 24 Nov
    final s1 = await shifts.open(by: cashier, openingCash: 50000);
    await sell(
      [(para, 'Strip', 2), (para, 'Tablet', 4)],
      PaymentMethod.cash,
      cashier,
    ); // 11.000, HPP 7.200
    await sell(
      [(amox, 'Kapsul', 10)],
      PaymentMethod.qris,
      cashier,
    ); // 15.000, HPP 10.000
    final batal = await sell(
      [(amox, 'Kapsul', 2)],
      PaymentMethod.cash,
      cashier,
    ); // 3.000 batal
    await sales.voidSale(saleId: batal.id, reason: 'uji', by: owner);
    await shifts.close(shiftId: s1.id, countedCash: 61000, by: cashier);

    // Selasa 25 Nov — Pemilik, dengan diskon total
    clock.advance(const Duration(days: 1));
    await shifts.open(by: owner, openingCash: 61000);
    await sell(
      [(para, 'Strip', 1)],
      PaymentMethod.cash,
      owner,
      discount: 500,
    ); // 4.000, HPP 3.000

    final week = await reports.build(
      ReportRange.days(DateTime(2026, 11, 24), DateTime(2026, 11, 25)),
    );
    expect(week.count, 3);
    expect(week.revenue, 11000 + 15000 + 4000);
    expect(week.cost, 7200 + 10000 + 3000);
    expect(week.grossProfit, 30000 - 20200);
    expect(week.cash, 15000);
    expect(week.qris, 15000);
    expect(week.discount, 500);
    expect(week.voidCount, 1);
    expect(week.voidTotal, 3000);
    expect(week.averageSale, 10000);
    expect(week.range.dayCount, 2);

    expect(week.days.map((d) => (d.day.day, d.revenue, d.count)), [
      (24, 26000, 2),
      (25, 4000, 1),
    ]);

    expect(week.products.map((p) => p.name), ['Paracetamol', 'Amoxicillin']);
    final p = week.products.first;
    expect(p.quantities, {'Strip': 3, 'Tablet': 4});
    expect(p.baseQuantity, 34);
    // Omzet produk = jumlah harga baris (diskon total tidak dibagi ke produk)
    expect(p.revenue, 9000 + 2000 + 4500);
    expect(week.products.last.quantities, {
      'Kapsul': 10,
    }, reason: 'yang dibatalkan tidak dihitung');

    expect(week.cashiers.map((c) => (c.name, c.revenue, c.count)), [
      ('Dewi', 26000, 2),
      ('Sari', 4000, 1),
    ]);

    expect(week.shifts.map((s) => s.openedByName), ['Sari', 'Dewi']);
    expect(week.shifts.last.difference, 0);

    final tuesday = await reports.build(
      ReportRange.day(DateTime(2026, 11, 25)),
    );
    expect(tuesday.revenue, 4000);
    expect(tuesday.shifts, hasLength(1));
  });

  test('laporan kosong tidak error', () async {
    final r = await reports.build(ReportRange.month(DateTime(2026, 11, 10)));
    expect(r.count, 0);
    expect(r.revenue, 0);
    expect(r.margin, 0);
    expect(r.averageSale, 0);
    expect(r.days, isEmpty);
    expect(r.range.dayCount, 30);
  });
}
