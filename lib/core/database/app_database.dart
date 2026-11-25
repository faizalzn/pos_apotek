import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'tables.dart';

export 'tables.dart';

part 'app_database.g.dart';

/// Database lokal aplikasi (SQLite via Drift). Lihat docs/DATABASE.md.
@DriftDatabase(tables: [Users, AppSettings])
class AppDatabase extends _$AppDatabase {
  /// [executor] dapat diganti (mis. database di memori) untuk pengujian.
  AppDatabase([QueryExecutor? executor])
      : super(executor ?? driftDatabase(name: 'pos_apotek'));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}

/// Satu instance database untuk seluruh aplikasi.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
