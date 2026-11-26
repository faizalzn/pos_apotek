import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/clock.dart';
import '../../../core/database/app_database.dart';
import '../../../core/format.dart';
import '../../../core/xlsx.dart';
import '../../products/data/product_models.dart';
import '../../products/data/product_repository.dart';
import '../../settings/data/settings_repository.dart';
import 'shift_service.dart';

/// Laporan Excel satu shift: ringkasan kas, transaksi, rincian barang, rekap
/// produk, kas masuk/keluar, dan stok saat dibuat.
class ShiftExcelBuilder {
  ShiftExcelBuilder(this._db, this._shifts, this._products, this._now);

  final AppDatabase _db;
  final ShiftService _shifts;
  final ProductRepository _products;
  final DateTime Function() _now;

  /// Nama file, mis. `shift_Dewi_2026-11-25_0700.xlsx`.
  static String fileName(ShiftSummary s) {
    String two(int n) => n.toString().padLeft(2, '0');
    final d = s.shift.openedAt;
    final who = s.openedByName.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    return 'shift_${who}_${d.year}-${two(d.month)}-${two(d.day)}_'
        '${two(d.hour)}${two(d.minute)}.xlsx';
  }

  Future<Uint8List> build(String shiftId, {required String storeName}) async {
    final s = await _shifts.summary(shiftId);
    final now = _now();

    final sales =
        await (_db.select(_db.sales).join([
                innerJoin(
                  _db.users,
                  _db.users.id.equalsExp(_db.sales.cashierId),
                ),
              ])
              ..where(_db.sales.shiftId.equals(shiftId))
              ..orderBy([OrderingTerm.asc(_db.sales.createdAt)]))
            .get();
    final saleRows = [
      for (final r in sales)
        (r.readTable(_db.sales), r.readTable(_db.users).name),
    ];
    final saleById = {for (final (sale, _) in saleRows) sale.id: sale};
    final items =
        await (_db.select(_db.saleItems)
              ..where((i) => i.saleId.isIn(saleById.keys))
              ..orderBy([(i) => OrderingTerm.asc(i.createdAt)]))
            .get();

    return buildXlsx([
      _summarySheet(s, storeName, now),
      _salesSheet(saleRows),
      _itemsSheet(items, saleById),
      _productsSheet(items, saleById),
      _cashSheet(s),
      _stockSheet(await _products.loadAll(), now),
    ]);
  }

  XlsxSheet _summarySheet(ShiftSummary s, String store, DateTime now) {
    final sh = s.shift;
    final sheet = XlsxSheet('Ringkasan', widths: [30, 22])
      ..add([
        XlsxCell(
          'Laporan Shift${store.isEmpty ? '' : ' · $store'}',
          XlsxStyle.title,
        ),
      ])
      ..add(['Dibuat', now])
      ..blank()
      ..add(['Kasir (buka)', s.openedByName])
      ..add(['Dibuka', sh.openedAt])
      ..add(['Ditutup', sh.closedAt ?? 'Masih berjalan'])
      ..add(['Ditutup oleh', s.closedByName ?? '-'])
      ..blank()
      ..add(['PENJUALAN', null], style: XlsxStyle.header)
      ..add(['Jumlah transaksi', XlsxCell(s.saleCount)])
      ..add(['Tunai', s.cashSales])
      ..add(['QRIS', s.qrisSales])
      ..add(['Total penjualan', XlsxCell(s.totalSales, XlsxStyle.boldMoney)])
      ..add(['Transaksi dibatalkan', XlsxCell(s.voidCount)])
      ..blank()
      ..add(['KAS LACI', null], style: XlsxStyle.header)
      ..add(['Modal awal', sh.openingCash])
      ..add(['+ Penjualan tunai', s.cashSales])
      ..add(['+ Kas masuk', s.cashIn])
      ..add(['− Kas keluar', s.cashOut])
      ..add(['− Pengembalian (batal shift lain)', s.refunds])
      ..add([
        'Seharusnya di laci',
        XlsxCell(s.expectedCash, XlsxStyle.boldMoney),
      ]);
    if (sh.countedCash != null) {
      final d = s.difference ?? 0;
      sheet
        ..add(['Dihitung kasir', XlsxCell(sh.countedCash, XlsxStyle.boldMoney)])
        ..add([
          'Selisih (+ lebih / − kurang)',
          XlsxCell(d, XlsxStyle.boldMoney),
        ])
        ..add(['Keterangan', d == 0 ? 'Pas' : (d > 0 ? 'Lebih' : 'Kurang')]);
    }
    if (sh.closingNote.isNotEmpty) sheet.add(['Catatan', sh.closingNote]);
    return sheet;
  }

  XlsxSheet _salesSheet(List<(Sale, String)> rows) {
    final sheet =
        XlsxSheet(
          'Transaksi',
          widths: [16, 18, 12, 12, 8, 12, 12, 12, 12, 12, 12, 12, 12, 24],
          freezeRows: 1,
        )..add([
          'No. transaksi', 'Waktu', 'Kasir', 'Status', 'Bayar', 'Subtotal', //
          'Diskon barang', 'Diskon belanja', 'Total', 'Diterima', 'Kembalian',
          'HPP', 'Laba kotor', 'Alasan batal',
        ], style: XlsxStyle.header);
    var total = 0, cost = 0.0;
    for (final (s, cashier) in rows) {
      final done = s.status == SaleStatus.completed;
      if (done) {
        total += s.total;
        cost += s.costTotal;
      }
      sheet.add([
        s.number, s.createdAt, cashier, done ? 'Selesai' : 'Dibatalkan', //
        s.paymentMethod == PaymentMethod.qris ? 'QRIS' : 'Tunai',
        s.subtotal, s.itemDiscount, s.discount, s.total, s.amountPaid,
        s.change, s.costTotal.round(), (s.total - s.costTotal).round(),
        s.voidReason.isEmpty ? null : s.voidReason,
      ]);
    }
    sheet.add([
      XlsxCell('TOTAL (selesai)', XlsxStyle.bold), null, null, null, null, //
      null, null, null, XlsxCell(total, XlsxStyle.boldMoney), null, null,
      XlsxCell(cost.round(), XlsxStyle.boldMoney),
      XlsxCell((total - cost).round(), XlsxStyle.boldMoney),
    ]);
    return sheet;
  }

  XlsxSheet _itemsSheet(List<SaleItem> items, Map<String, Sale> sales) {
    final sheet =
        XlsxSheet(
          'Rincian Barang',
          widths: [16, 18, 30, 10, 8, 12, 12, 12, 12, 12, 12],
          freezeRows: 1,
        )..add([
          'No. transaksi', 'Waktu', 'Produk', 'Satuan', 'Jumlah', 'Harga', //
          'Diskon', 'Total', 'HPP', 'Laba kotor', 'Status',
        ], style: XlsxStyle.header);
    for (final i in items) {
      final s = sales[i.saleId]!;
      sheet.add([
        s.number,
        s.createdAt,
        i.productName,
        i.unitName,
        XlsxCell(i.quantity), //
        i.unitPrice, i.discount, i.lineTotal, i.costTotal.round(),
        (i.lineTotal - i.costTotal).round(),
        s.status == SaleStatus.completed ? 'Selesai' : 'Dibatalkan',
      ]);
    }
    return sheet;
  }

  XlsxSheet _productsSheet(List<SaleItem> items, Map<String, Sale> sales) {
    final byProduct =
        <
          String,
          ({String name, Map<String, int> qty, int revenue, double cost})
        >{};
    for (final i in items) {
      if (sales[i.saleId]!.status != SaleStatus.completed) continue;
      final p =
          byProduct[i.productId] ??
          (name: i.productName, qty: <String, int>{}, revenue: 0, cost: 0.0);
      p.qty[i.unitName] = (p.qty[i.unitName] ?? 0) + i.quantity;
      byProduct[i.productId] = (
        name: p.name,
        qty: p.qty,
        revenue: p.revenue + i.lineTotal,
        cost: p.cost + i.costTotal,
      );
    }
    final list = byProduct.values.toList()
      ..sort((a, b) => b.revenue.compareTo(a.revenue));
    final sheet =
        XlsxSheet('Rekap Produk', widths: [30, 26, 14, 14, 14], freezeRows: 1)
          ..add([
            'Produk',
            'Terjual',
            'Omzet',
            'HPP',
            'Laba kotor',
          ], style: XlsxStyle.header);
    for (final p in list) {
      sheet.add([
        p.name,
        p.qty.entries
            .map((e) => '${formatNumber(e.value)} ${e.key}')
            .join(', '),
        p.revenue,
        p.cost.round(),
        (p.revenue - p.cost).round(),
      ]);
    }
    return sheet;
  }

  XlsxSheet _cashSheet(ShiftSummary s) {
    final sheet =
        XlsxSheet(
          'Kas Masuk-Keluar',
          widths: [17, 12, 14, 34, 14],
          freezeRows: 1,
        )..add([
          'Waktu',
          'Jenis',
          'Jumlah',
          'Keterangan',
          'Oleh',
        ], style: XlsxStyle.header);
    for (final e in s.entries) {
      sheet.add([
        e.entry.createdAt,
        e.entry.type.label,
        e.signedAmount,
        e.entry.note,
        e.userName,
      ]);
    }
    if (s.entries.isEmpty) sheet.add(['Tidak ada kas masuk/keluar']);
    return sheet;
  }

  XlsxSheet _stockSheet(List<ProductSummary> products, DateTime now) {
    final sheet =
        XlsxSheet('Stok', widths: [30, 22, 18, 24, 14, 12, 16], freezeRows: 1)
          ..add([
            'Produk', 'Golongan', 'Kategori', 'Stok', 'Stok (satuan kecil)', //
            'ED terdekat', 'Status',
          ], style: XlsxStyle.header);
    final active = products.where((p) => p.product.isActive).toList()
      ..sort(
        (a, b) => a.product.name.toLowerCase().compareTo(
          b.product.name.toLowerCase(),
        ),
      );
    for (final p in active) {
      final expiry = p.expiryStatus(now);
      final status = [
        if (p.isOutOfStock) 'Habis' else if (p.isLowStock) 'Menipis',
        if (expiry == ExpiryStatus.expired) 'Kedaluwarsa',
        if (expiry == ExpiryStatus.soon) 'Hampir ED',
      ].join(', ');
      sheet.add([
        p.product.name,
        p.product.drugClass.label,
        p.product.category.isEmpty ? null : p.product.category,
        formatStock(p.stock, p.units),
        XlsxCell('${formatNumber(p.stock)} ${p.baseUnit.name}'),
        formatExpiry(p.nearestExpiry),
        status.isEmpty ? 'Aman' : status,
      ]);
    }
    return sheet;
  }
}

/// Membuat file Excel shift di folder sementara.
class ShiftExcelService {
  ShiftExcelService(this._builder, this._shifts, this._settings, this._tempDir);

  final ShiftExcelBuilder _builder;
  final ShiftService _shifts;
  final SettingsRepository _settings;
  final Future<Directory> Function() _tempDir;

  Future<File> writeFile(String shiftId) async {
    final summary = await _shifts.summary(shiftId);
    final bytes = await _builder.build(
      shiftId,
      storeName: await _settings.get(SettingKeys.storeName) ?? '',
    );
    final dir = Directory('${(await _tempDir()).path}/excel');
    await dir.create(recursive: true);
    final file = File('${dir.path}/${ShiftExcelBuilder.fileName(summary)}');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }
}

final shiftExcelProvider = Provider<ShiftExcelService>((ref) {
  final shifts = ref.watch(shiftServiceProvider);
  return ShiftExcelService(
    ShiftExcelBuilder(
      ref.watch(databaseProvider),
      shifts,
      ref.watch(productRepositoryProvider),
      ref.watch(clockProvider),
    ),
    shifts,
    ref.watch(settingsRepositoryProvider),
    getTemporaryDirectory,
  );
});
