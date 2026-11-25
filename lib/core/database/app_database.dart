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
  ],
)
class AppDatabase extends _$AppDatabase {
  /// [executor] dapat diganti (mis. database di memori) untuk pengujian.
  AppDatabase([QueryExecutor? executor])
      : super(executor ?? driftDatabase(name: 'pos_apotek'));

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _createIndexes();
        },
        // Setiap versi baru: tambahkan langkah di sini, lalu jalankan
        // `dart run drift_dev make-migrations` (lihat docs/DATABASE.md).
        onUpgrade: stepByStep(
          from1To2: (m, schema) async {
            await m.createTable(schema.products);
            await m.createTable(schema.productUnits);
            await m.createTable(schema.batches);
            await m.createTable(schema.stockMovements);
            await _createIndexes();
          },
        ),
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  Future<void> _createIndexes() async {
    for (final sql in const [
      'CREATE INDEX IF NOT EXISTS idx_units_product ON product_units (product_id)',
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_units_barcode ON product_units (barcode) WHERE barcode IS NOT NULL',
      'CREATE INDEX IF NOT EXISTS idx_batches_product ON batches (product_id, expiry_date)',
      'CREATE INDEX IF NOT EXISTS idx_movements_product ON stock_movements (product_id, created_at)',
    ]) {
      await customStatement(sql);
    }
  }
}

/// Satu instance database untuk seluruh aplikasi.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
