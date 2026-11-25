import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/clock.dart';
import '../../../core/database/app_database.dart';
import '../../shift/data/shift_service.dart';

/// Rentang tanggal laporan: [from] (termasuk) s.d. [to] (tidak termasuk).
class ReportRange {
  const ReportRange(this.from, this.to);

  /// Satu hari penuh.
  factory ReportRange.day(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return ReportRange(d, DateTime(d.year, d.month, d.day + 1));
  }

  /// Hari [first] s.d. [last], keduanya termasuk.
  factory ReportRange.days(DateTime first, DateTime last) => ReportRange(
    DateTime(first.year, first.month, first.day),
    DateTime(last.year, last.month, last.day + 1),
  );

  factory ReportRange.month(DateTime day) => ReportRange(
    DateTime(day.year, day.month),
    DateTime(day.year, day.month + 1),
  );

  final DateTime from;
  final DateTime to;

  int get dayCount => DateTime(
    to.year,
    to.month,
    to.day,
  ).difference(DateTime(from.year, from.month, from.day)).inDays;

  @override
  bool operator ==(Object other) =>
      other is ReportRange && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}

class DaySales {
  const DaySales({
    required this.day,
    required this.revenue,
    required this.count,
    required this.profit,
  });
  final DateTime day;
  final int revenue;
  final int count;
  final int profit;
}

/// Penjualan satu produk dalam rentang laporan.
class ProductSales {
  ProductSales({required this.productId, required this.name});

  final String productId;
  String name;

  /// Satuan terjual, mis. {"Strip": 3, "Tablet": 12}.
  final Map<String, int> quantities = {};
  int baseQuantity = 0;
  int revenue = 0;
  double cost = 0;

  int get profit => (revenue - cost).round();
}

class CashierSales {
  const CashierSales({
    required this.name,
    required this.revenue,
    required this.count,
  });
  final String name;
  final int revenue;
  final int count;
}

class SalesReport {
  const SalesReport({
    required this.range,
    required this.revenue,
    required this.count,
    required this.cost,
    required this.cash,
    required this.qris,
    required this.itemDiscount,
    required this.discount,
    required this.voidCount,
    required this.voidTotal,
    required this.days,
    required this.products,
    required this.cashiers,
    required this.shifts,
  });

  final ReportRange range;

  /// Omzet: total transaksi selesai (sesudah diskon).
  final int revenue;
  final int count;

  /// Harga beli barang terjual (FEFO).
  final double cost;
  final int cash;
  final int qris;
  final int itemDiscount;
  final int discount;
  final int voidCount;
  final int voidTotal;
  final List<DaySales> days;

  /// Terlaris (omzet terbesar) lebih dulu.
  final List<ProductSales> products;
  final List<CashierSales> cashiers;
  final List<ShiftSummary> shifts;

  int get grossProfit => (revenue - cost).round();
  int get averageSale => count == 0 ? 0 : (revenue / count).round();

  /// Persentase laba kotor terhadap omzet.
  double get margin => revenue == 0 ? 0 : grossProfit / revenue * 100;
  int get totalDiscount => itemDiscount + discount;
}

class ReportService {
  ReportService(this._db, this._shifts);

  final AppDatabase _db;
  final ShiftService _shifts;

  Future<SalesReport> build(ReportRange range) async {
    final vars = [
      Variable.withDateTime(range.from),
      Variable.withDateTime(range.to),
    ];
    const inRange = 'created_at >= ? AND created_at < ?';

    final t = await _db
        .customSelect(
          '''
      SELECT
        COUNT(CASE WHEN status = 'completed' THEN 1 END) AS done,
        COALESCE(SUM(CASE WHEN status = 'completed' THEN total END), 0) AS revenue,
        COALESCE(SUM(CASE WHEN status = 'completed' THEN cost_total END), 0.0) AS cost,
        COALESCE(SUM(CASE WHEN status = 'completed' AND payment_method = 'cash' THEN total END), 0) AS cash,
        COALESCE(SUM(CASE WHEN status = 'completed' AND payment_method = 'qris' THEN total END), 0) AS qris,
        COALESCE(SUM(CASE WHEN status = 'completed' THEN item_discount END), 0) AS item_discount,
        COALESCE(SUM(CASE WHEN status = 'completed' THEN discount END), 0) AS discount,
        COUNT(CASE WHEN status = 'voided' THEN 1 END) AS voided,
        COALESCE(SUM(CASE WHEN status = 'voided' THEN total END), 0) AS void_total
      FROM sales WHERE $inRange
      ''',
          variables: vars,
          readsFrom: {_db.sales},
        )
        .getSingle();

    // Per hari: tanggal disimpan sebagai teks ISO, 10 karakter pertama = yyyy-MM-dd.
    final dayRows = await _db
        .customSelect(
          '''
      SELECT substr(created_at, 1, 10) AS day, COUNT(*) AS n,
             SUM(total) AS revenue, SUM(total - cost_total) AS profit
      FROM sales WHERE status = 'completed' AND $inRange
      GROUP BY day ORDER BY day
      ''',
          variables: vars,
          readsFrom: {_db.sales},
        )
        .get();

    final itemRows = await _db
        .customSelect(
          '''
      SELECT i.product_id, i.product_name, i.unit_name,
             SUM(i.quantity) AS qty, SUM(i.quantity * i.multiplier) AS base_qty,
             SUM(i.line_total) AS revenue, SUM(i.cost_total) AS cost
      FROM sale_items i JOIN sales s ON s.id = i.sale_id
      WHERE s.status = 'completed' AND s.created_at >= ? AND s.created_at < ?
      GROUP BY i.product_id, i.unit_name
      ''',
          variables: vars,
          readsFrom: {_db.sales, _db.saleItems},
        )
        .get();

    final cashierRows = await _db
        .customSelect(
          '''
      SELECT u.name, COUNT(*) AS n, SUM(s.total) AS revenue
      FROM sales s JOIN users u ON u.id = s.cashier_id
      WHERE s.status = 'completed' AND s.created_at >= ? AND s.created_at < ?
      GROUP BY s.cashier_id ORDER BY revenue DESC
      ''',
          variables: vars,
          readsFrom: {_db.sales, _db.users},
        )
        .get();

    final products = <String, ProductSales>{};
    for (final r in itemRows) {
      final id = r.read<String>('product_id');
      final p = products.putIfAbsent(
        id,
        () => ProductSales(productId: id, name: r.read<String>('product_name')),
      );
      p.quantities[r.read<String>('unit_name')] = r.read<int>('qty');
      p.baseQuantity += r.read<int>('base_qty');
      p.revenue += r.read<int>('revenue');
      p.cost += _real(r, 'cost');
    }
    final productList = products.values.toList()
      ..sort((a, b) => b.revenue.compareTo(a.revenue));

    return SalesReport(
      range: range,
      revenue: t.read<int>('revenue'),
      count: t.read<int>('done'),
      cost: _real(t, 'cost'),
      cash: t.read<int>('cash'),
      qris: t.read<int>('qris'),
      itemDiscount: t.read<int>('item_discount'),
      discount: t.read<int>('discount'),
      voidCount: t.read<int>('voided'),
      voidTotal: t.read<int>('void_total'),
      days: [
        for (final r in dayRows)
          DaySales(
            day: DateTime.parse(r.read<String>('day')),
            revenue: r.read<int>('revenue'),
            count: r.read<int>('n'),
            profit: _real(r, 'profit').round(),
          ),
      ],
      products: productList,
      cashiers: [
        for (final r in cashierRows)
          CashierSales(
            name: r.read<String>('name'),
            revenue: r.read<int>('revenue'),
            count: r.read<int>('n'),
          ),
      ],
      shifts: await _shifts.inRange(range.from, range.to),
    );
  }

  /// Laporan yang diperbarui otomatis saat ada transaksi / shift berubah.
  Stream<SalesReport> watch(ReportRange range) async* {
    yield await build(range);
    await for (final _ in _db.tableUpdates(
      TableUpdateQuery.onAllTables([_db.sales, _db.shifts, _db.cashEntries]),
    )) {
      yield await build(range);
    }
  }
}

/// Nilai REAL dari SQLite bisa terbaca sebagai bilangan bulat.
double _real(QueryRow row, String column) =>
    (row.data[column] as num? ?? 0).toDouble();

final reportServiceProvider = Provider<ReportService>(
  (ref) => ReportService(
    ref.watch(databaseProvider),
    ref.watch(shiftServiceProvider),
  ),
);

final salesReportProvider = StreamProvider.family<SalesReport, ReportRange>(
  (ref, range) => ref.watch(reportServiceProvider).watch(range),
);

/// Hari ini menurut jam aplikasi.
final todayProvider = Provider<DateTime>((ref) {
  final now = ref.watch(clockProvider)();
  return DateTime(now.year, now.month, now.day);
});
