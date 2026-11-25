import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/clock.dart';
import '../../../core/database/app_database.dart';
import '../../auth/data/user_repository.dart' show UserRuleException;
import 'product_models.dart';

/// Kesalahan isian produk/stok. [message] siap ditampilkan ke pengguna.
typedef ProductRuleException = UserRuleException;

/// Kunci pengaturan umum lama peringatan ED (hari). Lihat [SettingKeys].
const nearExpirySettingKey = 'stock.near_expiry_days';

class ProductRepository {
  ProductRepository(this._db, this._now);

  final AppDatabase _db;
  final Clock _now;

  static const _uuid = Uuid();

  // ───────────────────────────── Membaca ─────────────────────────────

  /// Semua produk (termasuk arsip) beserta satuan & batch-nya. Otomatis
  /// diperbarui saat produk, satuan, atau stok berubah.
  Stream<List<ProductSummary>> watchAll() {
    final updates = _db.tableUpdates(
      TableUpdateQuery.onAllTables([
        _db.products,
        _db.productUnits,
        _db.batches,
        _db.appSettings,
      ]),
    );
    late StreamController<List<ProductSummary>> controller;
    StreamSubscription<void>? sub;
    controller = StreamController<List<ProductSummary>>(
      onListen: () async {
        Future<void> emit() async {
          try {
            final data = await loadAll();
            if (!controller.isClosed) controller.add(data);
          } catch (e, s) {
            if (!controller.isClosed) controller.addError(e, s);
          }
        }

        await emit();
        sub = updates.listen((_) => emit());
      },
      onCancel: () => sub?.cancel(),
    );
    return controller.stream;
  }

  Future<List<ProductSummary>> loadAll() async {
    final products =
        await (_db.select(_db.products)..orderBy([
              (p) => OrderingTerm.asc(p.name.collate(Collate.noCase)),
            ]))
            .get();
    final units = await _db.select(_db.productUnits).get();
    final batches = await (_db.select(
      _db.batches,
    )..where((b) => b.quantity.isBiggerThanValue(0))).get();

    final unitsBy = <String, List<ProductUnit>>{};
    for (final u in units) {
      (unitsBy[u.productId] ??= []).add(u);
    }
    final setting = await (_db.select(
      _db.appSettings,
    )..where((s) => s.key.equals(nearExpirySettingKey))).getSingleOrNull();
    final defaultDays =
        int.tryParse(setting?.value ?? '') ?? defaultNearExpiryDays;

    final batchesBy = <String, List<StockBatch>>{};
    for (final b in _sortFefo(batches)) {
      (batchesBy[b.productId] ??= []).add(b);
    }
    return [
      for (final p in products)
        if (unitsBy[p.id] case final us?)
          ProductSummary(
            product: p,
            units: us,
            batches: batchesBy[p.id] ?? const [],
            defaultExpiryDays: defaultDays,
          ),
    ];
  }

  Stream<ProductSummary?> watchOne(String productId) => watchAll().map(
    (list) => list.where((p) => p.product.id == productId).firstOrNull,
  );

  Future<ProductSummary?> getOne(String productId) async =>
      (await loadAll()).where((p) => p.product.id == productId).firstOrNull;

  /// Mencari satuan berdasarkan barcode (untuk scan di kasir/pencarian).
  Future<({Product product, ProductUnit unit})?> findByBarcode(
    String barcode,
  ) async {
    final code = barcode.trim();
    if (code.isEmpty) return null;
    final query = _db.select(_db.productUnits).join([
      innerJoin(
        _db.products,
        _db.products.id.equalsExp(_db.productUnits.productId),
      ),
    ])..where(_db.productUnits.barcode.equals(code));
    final row = await query.getSingleOrNull();
    if (row == null) return null;
    return (
      product: row.readTable(_db.products),
      unit: row.readTable(_db.productUnits),
    );
  }

  /// Daftar kategori yang pernah dipakai, untuk saran isian.
  Future<List<String>> categories() async {
    final rows =
        await (_db.selectOnly(_db.products, distinct: true)
              ..addColumns([_db.products.category])
              ..where(_db.products.category.isNotValue('')))
            .get();
    return rows.map((r) => r.read(_db.products.category)!).toList()..sort();
  }

  /// Nama satuan yang pernah dipakai (untuk pilihan cepat di formulir).
  Future<List<String>> unitNames() async {
    final rows =
        await (_db.selectOnly(_db.productUnits, distinct: true)
              ..addColumns([_db.productUnits.name]))
            .get();
    return rows.map((r) => r.read(_db.productUnits.name)!).toList()..sort();
  }

  /// Riwayat stok terbaru lebih dulu.
  Stream<List<MovementEntry>> watchMovements(String productId) {
    final query =
        _db.select(_db.stockMovements).join([
            leftOuterJoin(
              _db.users,
              _db.users.id.equalsExp(_db.stockMovements.userId),
            ),
            leftOuterJoin(
              _db.batches,
              _db.batches.id.equalsExp(_db.stockMovements.batchId),
            ),
          ])
          ..where(_db.stockMovements.productId.equals(productId))
          ..orderBy([OrderingTerm.desc(_db.stockMovements.createdAt)]);
    return query.watch().map(
      (rows) => [
        for (final r in rows)
          MovementEntry(
            movement: r.readTable(_db.stockMovements),
            userName: r.readTableOrNull(_db.users)?.name,
            batch: r.readTableOrNull(_db.batches),
          ),
      ],
    );
  }

  // ───────────────────────────── Produk ─────────────────────────────

  Future<Product> create(ProductInput input) async {
    final units = await _validate(input);
    final now = _now();
    final id = _uuid.v4();
    await _db.transaction(() async {
      await _db
          .into(_db.products)
          .insert(
            ProductsCompanion.insert(
              id: id,
              name: input.name.trim(),
              genericName: Value(input.genericName.trim()),
              category: Value(input.category.trim()),
              drugClass: input.drugClass,
              photoFile: Value(input.photoFile),
              minStock: Value(input.minStock),
              nearExpiryDays: Value(input.nearExpiryDays),
              createdAt: now,
              updatedAt: now,
            ),
          );
      for (final u in units) {
        await _insertUnit(id, u, now);
      }
    });
    return (await (_db.select(
      _db.products,
    )..where((p) => p.id.equals(id))).getSingle());
  }

  Future<void> update(String productId, ProductInput input) async {
    final units = await _validate(input, productId: productId);
    final now = _now();
    await _db.transaction(() async {
      await (_db.update(
        _db.products,
      )..where((p) => p.id.equals(productId))).write(
        ProductsCompanion(
          name: Value(input.name.trim()),
          genericName: Value(input.genericName.trim()),
          category: Value(input.category.trim()),
          drugClass: Value(input.drugClass),
          photoFile: Value(input.photoFile),
          minStock: Value(input.minStock),
          nearExpiryDays: Value(input.nearExpiryDays),
          updatedAt: Value(now),
        ),
      );
      final keepIds = units.map((u) => u.id).whereType<String>().toSet();
      await (_db.delete(_db.productUnits)..where(
            (u) => u.productId.equals(productId) & u.id.isNotIn(keepIds),
          ))
          .go();
      for (final u in units) {
        if (u.id == null) {
          await _insertUnit(productId, u, now);
        } else {
          await (_db.update(
            _db.productUnits,
          )..where((x) => x.id.equals(u.id!))).write(
            ProductUnitsCompanion(
              name: Value(u.name),
              multiplier: Value(u.multiplier),
              sellPrice: Value(u.sellPrice),
              barcode: Value(u.barcode),
              updatedAt: Value(now),
            ),
          );
        }
      }
    });
  }

  Future<void> setArchived(String productId, {required bool archived}) =>
      (_db.update(_db.products)..where((p) => p.id.equals(productId))).write(
        ProductsCompanion(isActive: Value(!archived), updatedAt: Value(_now())),
      );

  Future<void> _insertUnit(String productId, UnitInput u, DateTime now) => _db
      .into(_db.productUnits)
      .insert(
        ProductUnitsCompanion.insert(
          id: _uuid.v4(),
          productId: productId,
          name: u.name,
          multiplier: u.multiplier,
          sellPrice: u.sellPrice,
          barcode: Value(u.barcode),
          createdAt: now,
          updatedAt: now,
        ),
      );

  /// Memeriksa isian dan mengembalikan satuan yang sudah dirapikan.
  Future<List<UnitInput>> _validate(
    ProductInput input, {
    String? productId,
  }) async {
    if (input.name.trim().isEmpty) {
      throw const ProductRuleException('Nama produk wajib diisi');
    }
    if (input.nearExpiryDays case final d? when d < 1) {
      throw const ProductRuleException('Lama peringatan ED minimal 1 hari');
    }
    if (input.minStock < 0) {
      throw const ProductRuleException('Stok minimum tidak boleh negatif');
    }
    if (input.units.isEmpty) {
      throw const ProductRuleException('Minimal harus ada satu satuan');
    }

    final cleaned = [
      for (final u in input.units)
        UnitInput(
          id: u.id,
          name: u.name.trim(),
          multiplier: u.multiplier,
          sellPrice: u.sellPrice,
          barcode: (u.barcode?.trim().isEmpty ?? true)
              ? null
              : u.barcode!.trim(),
        ),
    ];

    if (cleaned.where((u) => u.multiplier == 1).length != 1) {
      throw const ProductRuleException(
        'Harus ada tepat satu satuan terkecil (isi = 1)',
      );
    }
    final names = <String>{};
    final multipliers = <int>{};
    final barcodes = <String>{};
    for (final u in cleaned) {
      if (u.name.isEmpty) {
        throw const ProductRuleException('Nama satuan wajib diisi');
      }
      if (u.multiplier < 1) {
        throw ProductRuleException('Isi satuan "${u.name}" minimal 1');
      }
      if (u.sellPrice < 0) {
        throw ProductRuleException('Harga "${u.name}" tidak boleh negatif');
      }
      if (!names.add(u.name.toLowerCase())) {
        throw ProductRuleException('Satuan "${u.name}" ditulis dua kali');
      }
      if (!multipliers.add(u.multiplier)) {
        throw ProductRuleException(
          'Dua satuan tidak boleh punya isi yang sama (${u.multiplier})',
        );
      }
      if (u.barcode != null && !barcodes.add(u.barcode!)) {
        throw ProductRuleException('Barcode ${u.barcode} dipakai dua kali');
      }
    }

    for (final code in barcodes) {
      final existing = await findByBarcode(code);
      if (existing != null && existing.product.id != productId) {
        throw ProductRuleException(
          'Barcode $code sudah dipakai produk "${existing.product.name}"',
        );
      }
    }
    return cleaned;
  }

  // ───────────────────────────── Stok ─────────────────────────────

  /// Mencatat stok masuk. [quantity] dan [costPerSelectedUnit] dalam satuan
  /// [unit] yang dipilih; disimpan dalam satuan terkecil.
  ///
  /// StockBatch dengan nomor & ED yang sama digabung (harga beli dirata-rata).
  Future<void> receiveStock({
    required String productId,
    required ProductUnit unit,
    required int quantity,
    required DateTime? expiryDate,
    String batchNumber = '',
    double? costPerSelectedUnit,
    String? userId,
    String note = '',
  }) async {
    if (quantity <= 0) {
      throw const ProductRuleException('Jumlah harus lebih dari 0');
    }
    final baseQty = quantity * unit.multiplier;
    final now = _now();
    final batchNo = batchNumber.trim();

    await _db.transaction(() async {
      final cost = costPerSelectedUnit != null
          ? costPerSelectedUnit / unit.multiplier
          : await _lastCost(productId);

      StockBatch? existing;
      if (batchNo.isNotEmpty) {
        final candidates =
            await (_db.select(_db.batches)..where(
                  (b) =>
                      b.productId.equals(productId) &
                      b.batchNumber.equals(batchNo),
                ))
                .get();
        existing = candidates
            .where((b) => _sameDay(b.expiryDate, expiryDate))
            .firstOrNull;
      }

      final String batchId;
      if (existing != null) {
        batchId = existing.id;
        final total = existing.quantity + baseQty;
        final avgCost = total == 0
            ? cost
            : (existing.costPerUnit * existing.quantity + cost * baseQty) /
                  total;
        await (_db.update(
          _db.batches,
        )..where((b) => b.id.equals(batchId))).write(
          BatchesCompanion(
            quantity: Value(total),
            costPerUnit: Value(avgCost),
            updatedAt: Value(now),
          ),
        );
      } else {
        batchId = _uuid.v4();
        await _db
            .into(_db.batches)
            .insert(
              BatchesCompanion.insert(
                id: batchId,
                productId: productId,
                batchNumber: Value(batchNo),
                expiryDate: Value(expiryDate),
                quantity: baseQty,
                costPerUnit: Value(cost),
                receivedAt: now,
                createdAt: now,
                updatedAt: now,
              ),
            );
      }
      await _addMovement(
        productId: productId,
        batchId: batchId,
        type: StockMovementType.stockIn,
        quantity: baseQty,
        userId: userId,
        note: note,
        now: now,
      );
    });
  }

  /// Mengubah jumlah stok satu batch menjadi [newQuantity] (stock opname).
  Future<void> adjustBatch({
    required String batchId,
    required int newQuantity,
    required String note,
    String? userId,
  }) async {
    if (newQuantity < 0) {
      throw const ProductRuleException('Jumlah tidak boleh negatif');
    }
    await _changeBatch(
      batchId: batchId,
      type: StockMovementType.adjustment,
      delta: (batch) => newQuantity - batch.quantity,
      note: note,
      userId: userId,
    );
  }

  /// Mengeluarkan stok karena kedaluwarsa/rusak.
  Future<void> disposeFromBatch({
    required String batchId,
    required int quantity,
    required String note,
    String? userId,
  }) async {
    if (quantity <= 0) {
      throw const ProductRuleException('Jumlah harus lebih dari 0');
    }
    await _changeBatch(
      batchId: batchId,
      type: StockMovementType.disposal,
      delta: (batch) {
        if (quantity > batch.quantity) {
          throw ProductRuleException(
            'Hanya ada ${batch.quantity} di batch ini',
          );
        }
        return -quantity;
      },
      note: note,
      userId: userId,
    );
  }

  /// Mengambil stok mengikuti FEFO (ED terdekat dulu). StockBatch kedaluwarsa
  /// tidak diambil. Dipanggil di dalam transaksi penjualan.
  Future<List<BatchAllocation>> consumeFefo({
    required String productId,
    required int quantity,
    StockMovementType type = StockMovementType.sale,
    String? userId,
    String? saleId,
    String note = '',
  }) {
    return _db.transaction(() async {
      final now = _now();
      final batches =
          _sortFefo(
                await (_db.select(_db.batches)..where(
                      (b) =>
                          b.productId.equals(productId) &
                          b.quantity.isBiggerThanValue(0),
                    ))
                    .get(),
              )
              .where(
                (b) =>
                    expiryStatusOf(b.expiryDate, now) != ExpiryStatus.expired,
              )
              .toList();

      final available = batches.fold(0, (s, b) => s + b.quantity);
      if (available < quantity) {
        throw InsufficientStockException(
          requested: quantity,
          available: available,
        );
      }

      final allocations = <BatchAllocation>[];
      var remaining = quantity;
      for (final b in batches) {
        if (remaining == 0) break;
        final take = remaining < b.quantity ? remaining : b.quantity;
        await (_db.update(_db.batches)..where((x) => x.id.equals(b.id))).write(
          BatchesCompanion(
            quantity: Value(b.quantity - take),
            updatedAt: Value(now),
          ),
        );
        await _addMovement(
          productId: productId,
          batchId: b.id,
          type: type,
          quantity: -take,
          userId: userId,
          saleId: saleId,
          note: note,
          now: now,
        );
        allocations.add(BatchAllocation(batch: b, quantity: take));
        remaining -= take;
      }
      return allocations;
    });
  }

  Future<void> _changeBatch({
    required String batchId,
    required StockMovementType type,
    required int Function(StockBatch batch) delta,
    required String note,
    String? userId,
  }) {
    return _db.transaction(() async {
      final batch = await (_db.select(
        _db.batches,
      )..where((b) => b.id.equals(batchId))).getSingle();
      final change = delta(batch);
      if (change == 0) return;
      final now = _now();
      await (_db.update(_db.batches)..where((b) => b.id.equals(batchId))).write(
        BatchesCompanion(
          quantity: Value(batch.quantity + change),
          updatedAt: Value(now),
        ),
      );
      await _addMovement(
        productId: batch.productId,
        batchId: batchId,
        type: type,
        quantity: change,
        userId: userId,
        note: note,
        now: now,
      );
    });
  }

  Future<void> _addMovement({
    required String productId,
    required String batchId,
    required StockMovementType type,
    required int quantity,
    required DateTime now,
    String? userId,
    String? saleId,
    String note = '',
  }) => _db
      .into(_db.stockMovements)
      .insert(
        StockMovementsCompanion.insert(
          id: _uuid.v4(),
          productId: productId,
          batchId: batchId,
          type: type,
          quantity: quantity,
          note: Value(note.trim()),
          userId: Value(userId),
          saleId: Value(saleId),
          createdAt: now,
          updatedAt: now,
        ),
      );

  /// Harga beli terakhir per satuan terkecil (untuk stok masuk oleh kasir
  /// yang tidak mengisi harga beli).
  Future<double> _lastCost(String productId) async {
    final last =
        await (_db.select(_db.batches)
              ..where((b) => b.productId.equals(productId))
              ..orderBy([(b) => OrderingTerm.desc(b.receivedAt)])
              ..limit(1))
            .getSingleOrNull();
    return last?.costPerUnit ?? 0;
  }

  static List<StockBatch> _sortFefo(List<StockBatch> batches) =>
      [...batches]..sort((a, b) {
        final ea = a.expiryDate;
        final eb = b.expiryDate;
        if (ea == null && eb != null) return 1;
        if (ea != null && eb == null) return -1;
        if (ea != null && eb != null) {
          final c = ea.compareTo(eb);
          if (c != 0) return c;
        }
        return a.receivedAt.compareTo(b.receivedAt);
      });

  static bool _sameDay(DateTime? a, DateTime? b) {
    if (a == null || b == null) return a == b;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

final productRepositoryProvider = Provider<ProductRepository>(
  (ref) =>
      ProductRepository(ref.watch(databaseProvider), ref.watch(clockProvider)),
);

final productsProvider = StreamProvider<List<ProductSummary>>(
  (ref) => ref.watch(productRepositoryProvider).watchAll(),
);

final productProvider = StreamProvider.family<ProductSummary?, String>(
  (ref, id) => ref.watch(productRepositoryProvider).watchOne(id),
);

final movementsProvider = StreamProvider.family<List<MovementEntry>, String>(
  (ref, id) => ref.watch(productRepositoryProvider).watchMovements(id),
);
