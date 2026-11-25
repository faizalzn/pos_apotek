import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_database.steps.dart';
import 'tables.dart';

export 'tables.dart';

part 'app_database.g.dart';

/// Database lokal aplikasi (SQLite via Drift). Lihat docs/DATABASE.md.
@DriftDatabase(
  tables: [
    Users,
    AppSettings,
    Products,
    ProductUnits,
    Batches,
    StockMovements,
    Sales,
    SaleItems,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// [executor] dapat diganti (mis. database di memori) untuk pengujian.
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'pos_apotek'));

  @override
  int get schemaVersion => 3;

  Future<void>? _closing;

  /// Aman dipanggil lebih dari sekali (mis. saat aplikasi dimulai ulang
  /// setelah pemulihan backup).
  @override
  Future<void> close() => _closing ??= super.close();

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _createAllIndexes();
    },
    // Setiap versi baru: tambahkan langkah di sini, lalu jalankan
    // `dart run drift_dev make-migrations` (lihat docs/DATABASE.md).
    onUpgrade: stepByStep(
      from1To2: (m, schema) async {
        await m.createTable(schema.products);
        await m.createTable(schema.productUnits);
        await m.createTable(schema.batches);
        await m.createTable(schema.stockMovements);
        await _createIndexes(version: 2);
      },
      from2To3: (m, schema) async {
        await m.addColumn(schema.products, schema.products.nearExpiryDays);
        await m.createTable(schema.sales);
        await m.createTable(schema.saleItems);
        await m.addColumn(schema.stockMovements, schema.stockMovements.saleId);
        await _createIndexes(version: 3);
      },
    ),
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// Indeks per versi skema. Langkah migrasi hanya boleh membuat indeks
  /// untuk versinya sendiri (kolom versi berikutnya belum ada).
  static const _indexes = {
    2: [
      'CREATE INDEX IF NOT EXISTS idx_units_product ON product_units (product_id)',
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_units_barcode ON product_units (barcode) WHERE barcode IS NOT NULL',
      'CREATE INDEX IF NOT EXISTS idx_batches_product ON batches (product_id, expiry_date)',
      'CREATE INDEX IF NOT EXISTS idx_movements_product ON stock_movements (product_id, created_at)',
    ],
    3: [
      'CREATE INDEX IF NOT EXISTS idx_movements_sale ON stock_movements (sale_id)',
      'CREATE INDEX IF NOT EXISTS idx_sales_created ON sales (created_at)',
      'CREATE INDEX IF NOT EXISTS idx_sale_items_sale ON sale_items (sale_id)',
    ],
  };

  Future<void> _createIndexes({required int version}) async {
    for (final sql in _indexes[version] ?? const <String>[]) {
      await customStatement(sql);
    }
  }

  Future<void> _createAllIndexes() async {
    for (final version in _indexes.keys) {
      await _createIndexes(version: version);
    }
  }
}

/// Satu instance database untuk seluruh aplikasi.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
