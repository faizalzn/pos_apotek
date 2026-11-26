import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../telegram/data/telegram_messages.dart' show StockNote;
import '../../telegram/data/telegram_service.dart' show telegramOutboxProvider;
import '../../../core/clock.dart';
import '../../../core/database/app_database.dart';
import '../../../core/format.dart';
import '../../auth/data/user_repository.dart' show UserRuleException;
import '../../products/data/product_models.dart';
import '../../products/data/product_repository.dart';
import '../application/cart_controller.dart';

/// Transaksi beserta nama kasir.
class SaleEntry {
  const SaleEntry({required this.sale, required this.cashierName});
  final Sale sale;
  final String cashierName;
}

class SaleDetail {
  const SaleDetail({
    required this.sale,
    required this.items,
    required this.cashierName,
    this.voidedByName,
  });

  final Sale sale;
  final List<SaleItem> items;
  final String cashierName;
  final String? voidedByName;
}

/// Penerima kabar penjualan (mis. notifikasi Telegram). Dipanggil di dalam
/// transaksi database, sehingga pesan tersimpan bersama datanya.
abstract interface class SaleNotifier {
  Future<void> saleCompleted(SaleDetail detail, List<StockNote> stock);
  Future<void> saleVoided(SaleDetail detail);
}

class SaleService {
  SaleService(this._db, this._products, this._now, {this.notifier});

  final AppDatabase _db;
  final ProductRepository _products;
  final Clock _now;
  final SaleNotifier? notifier;

  static const _uuid = Uuid();

  /// Menyimpan transaksi: mengurangi stok (FEFO), mencatat barang & harga beli.
  ///
  /// Semua dalam satu transaksi database — bila satu barang gagal (mis. stok
  /// habis), tidak ada yang tersimpan.
  Future<Sale> complete({
    required Cart cart,
    required PaymentMethod method,
    required int amountPaid,
    required AppUser cashier,
  }) async {
    if (cart.isEmpty) {
      throw const UserRuleException('Keranjang masih kosong');
    }
    if (cashier.role != UserRole.owner && cart.hasOwnerOnlyChanges) {
      throw const UserRuleException(
        'Hanya Pemilik yang bisa mengubah harga atau memberi diskon',
      );
    }
    for (final l in cart.lines) {
      if (l.quantity <= 0 || l.unitPrice < 0 || l.discount < 0) {
        throw UserRuleException('Isian ${l.productName} tidak valid');
      }
      if (l.discount > l.gross) {
        throw UserRuleException('Diskon ${l.productName} melebihi harganya');
      }
    }
    if (cart.discount < 0 || cart.total < 0) {
      throw const UserRuleException('Diskon melebihi total belanja');
    }
    final total = cart.total;
    if (method == PaymentMethod.cash && amountPaid < total) {
      throw const UserRuleException('Uang yang diterima kurang dari total');
    }
    final paid = method == PaymentMethod.qris ? total : amountPaid;

    return _db.transaction(() async {
      final shift = await (_db.select(_db.shifts)
            ..where((s) => s.status.equalsValue(ShiftStatus.open))
            ..limit(1))
          .getSingleOrNull();
      if (shift == null) {
        throw const UserRuleException('Buka shift dulu sebelum berjualan');
      }
      final now = _now();
      final saleId = _uuid.v4();
      final number = await _nextNumber(now);

      await _db
          .into(_db.sales)
          .insert(
            SalesCompanion.insert(
              id: saleId,
              number: number,
              cashierId: cashier.id,
              shiftId: Value(shift.id),
              subtotal: cart.subtotal,
              itemDiscount: Value(cart.itemDiscount),
              discount: Value(cart.discount),
              total: total,
              paymentMethod: method,
              amountPaid: paid,
              change: Value(paid - total),
              status: SaleStatus.completed,
              createdAt: now,
              updatedAt: now,
            ),
          );

      var costTotal = 0.0;
      for (final line in cart.lines) {
        final List<BatchAllocation> allocations;
        try {
          allocations = await _products.consumeFefo(
            productId: line.productId,
            quantity: line.baseQuantity,
            userId: cashier.id,
            saleId: saleId,
            note: number,
          );
        } on InsufficientStockException catch (e) {
          throw UserRuleException(
            'Stok ${line.productName} tidak cukup. Tersisa '
            '${formatNumber(e.available)} ${line.baseUnitName} yang layak jual.',
          );
        }
        final cost = allocations.fold(
          0.0,
          (s, a) => s + a.quantity * a.batch.costPerUnit,
        );
        costTotal += cost;
        await _db
            .into(_db.saleItems)
            .insert(
              SaleItemsCompanion.insert(
                id: _uuid.v4(),
                saleId: saleId,
                productId: line.productId,
                unitId: Value(line.unit.id),
                productName: line.productName,
                unitName: line.unit.name,
                multiplier: line.unit.multiplier,
                quantity: line.quantity,
                listPrice: line.unit.sellPrice,
                unitPrice: line.unitPrice,
                discount: Value(line.discount),
                lineTotal: line.total,
                costTotal: Value(cost),
                createdAt: now,
                updatedAt: now,
              ),
            );
      }
      await (_db.update(_db.sales)..where((s) => s.id.equals(saleId))).write(
        SalesCompanion(costTotal: Value(costTotal)),
      );
      final sale = await (_db.select(
        _db.sales,
      )..where((s) => s.id.equals(saleId))).getSingle();
      if (notifier case final n?) {
        await n.saleCompleted(await _detailOf(sale), await _stockNotes(cart));
      }
      return sale;
    });
  }

  /// Membatalkan transaksi (hanya Pemilik): stok dikembalikan ke batch asal.
  Future<void> voidSale({
    required String saleId,
    required String reason,
    required AppUser by,
  }) async {
    if (by.role != UserRole.owner) {
      throw const UserRuleException(
        'Hanya Pemilik yang bisa membatalkan transaksi',
      );
    }
    if (reason.trim().isEmpty) {
      throw const UserRuleException('Alasan pembatalan wajib diisi');
    }
    await _db.transaction(() async {
      final sale = await (_db.select(
        _db.sales,
      )..where((s) => s.id.equals(saleId))).getSingle();
      if (sale.status == SaleStatus.voided) {
        throw const UserRuleException('Transaksi ini sudah dibatalkan');
      }
      final now = _now();
      final movements =
          await (_db.select(_db.stockMovements)..where(
                (m) =>
                    m.saleId.equals(saleId) &
                    m.type.equalsValue(StockMovementType.sale),
              ))
              .get();
      for (final m in movements) {
        final batch = await (_db.select(
          _db.batches,
        )..where((b) => b.id.equals(m.batchId))).getSingle();
        await (_db.update(
          _db.batches,
        )..where((b) => b.id.equals(batch.id))).write(
          BatchesCompanion(
            quantity: Value(batch.quantity - m.quantity),
            updatedAt: Value(now),
          ),
        );
        await _db
            .into(_db.stockMovements)
            .insert(
              StockMovementsCompanion.insert(
                id: _uuid.v4(),
                productId: m.productId,
                batchId: m.batchId,
                type: StockMovementType.saleVoid,
                quantity: -m.quantity,
                note: Value('${sale.number}: ${reason.trim()}'),
                userId: Value(by.id),
                saleId: Value(saleId),
                createdAt: now,
                updatedAt: now,
              ),
            );
      }
      await (_db.update(_db.sales)..where((s) => s.id.equals(saleId))).write(
        SalesCompanion(
          status: const Value(SaleStatus.voided),
          voidReason: Value(reason.trim()),
          voidedBy: Value(by.id),
          voidedAt: Value(now),
          updatedAt: Value(now),
        ),
      );
      if (notifier case final n?) {
        final voided = await (_db.select(
          _db.sales,
        )..where((s) => s.id.equals(saleId))).getSingle();
        await n.saleVoided(await _detailOf(voided));
      }
    });
  }

  /// Produk yang baru saja menjadi menipis/habis karena transaksi ini.
  Future<List<StockNote>> _stockNotes(Cart cart) async {
    final sold = <String, int>{};
    for (final l in cart.lines) {
      sold[l.productId] = (sold[l.productId] ?? 0) + l.baseQuantity;
    }
    final notes = <StockNote>[];
    for (final MapEntry(key: id, value: qty) in sold.entries) {
      final p = await _products.getOne(id);
      if (p == null) continue;
      final after = p.stock;
      final before = after + qty;
      final limit = p.lowStockThreshold;
      if (after <= 0) {
        notes.add(StockNote(name: p.product.name, stockText: 'habis', out: true));
      } else if (after <= limit && before > limit) {
        notes.add(
          StockNote(
            name: p.product.name,
            stockText: formatStock(after, p.units),
            out: false,
          ),
        );
      }
    }
    return notes;
  }

  /// Transaksi pada tanggal [day] (waktu setempat), terbaru lebih dulu.
  Stream<List<SaleEntry>> watchDay(DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    final query =
        _db.select(_db.sales).join([
            innerJoin(_db.users, _db.users.id.equalsExp(_db.sales.cashierId)),
          ])
          ..where(
            _db.sales.createdAt.isBiggerOrEqualValue(start) &
                _db.sales.createdAt.isSmallerThanValue(end),
          )
          ..orderBy([OrderingTerm.desc(_db.sales.createdAt)]);
    return query.watch().map(
      (rows) => [
        for (final r in rows)
          SaleEntry(
            sale: r.readTable(_db.sales),
            cashierName: r.readTable(_db.users).name,
          ),
      ],
    );
  }

  Stream<SaleDetail?> watchDetail(String saleId) {
    final saleQuery = _db.select(_db.sales)..where((s) => s.id.equals(saleId));
    return saleQuery.watchSingleOrNull().asyncMap(
      (sale) => sale == null ? Future.value() : _detailOf(sale),
    );
  }

  /// Detail transaksi sekali baca (untuk struk).
  Future<SaleDetail?> getDetail(String saleId) async {
    final sale = await (_db.select(
      _db.sales,
    )..where((s) => s.id.equals(saleId))).getSingleOrNull();
    return sale == null ? null : _detailOf(sale);
  }

  Future<SaleDetail> _detailOf(Sale sale) async {
    final saleId = sale.id;
    final items =
        await (_db.select(_db.saleItems)
              ..where((i) => i.saleId.equals(saleId))
              ..orderBy([(i) => OrderingTerm.asc(i.createdAt)]))
            .get();
    Future<String?> nameOf(String? id) async => id == null
        ? null
        : (await (_db.select(
            _db.users,
          )..where((u) => u.id.equals(id))).getSingleOrNull())?.name;
    return SaleDetail(
      sale: sale,
      items: items,
      cashierName: await nameOf(sale.cashierId) ?? '-',
      voidedByName: await nameOf(sale.voidedBy),
    );
  }

  /// Nomor transaksi `yyMMdd-NNNN`, urut per hari.
  Future<String> _nextNumber(DateTime now) async {
    String two(int n) => n.toString().padLeft(2, '0');
    final prefix = '${two(now.year % 100)}${two(now.month)}${two(now.day)}';
    final last =
        await (_db.select(_db.sales)
              ..where((s) => s.number.like('$prefix-%'))
              ..orderBy([(s) => OrderingTerm.desc(s.number)])
              ..limit(1))
            .getSingleOrNull();
    final next = last == null ? 1 : int.parse(last.number.split('-').last) + 1;
    return '$prefix-${next.toString().padLeft(4, '0')}';
  }
}

final saleServiceProvider = Provider<SaleService>(
  (ref) => SaleService(
    ref.watch(databaseProvider),
    ref.watch(productRepositoryProvider),
    ref.watch(clockProvider),
    notifier: ref.watch(telegramOutboxProvider),
  ),
);

final salesOfDayProvider = StreamProvider.family<List<SaleEntry>, DateTime>(
  (ref, day) => ref.watch(saleServiceProvider).watchDay(day),
);

final saleDetailProvider = StreamProvider.family<SaleDetail?, String>(
  (ref, id) => ref.watch(saleServiceProvider).watchDetail(id),
);
