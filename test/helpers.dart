import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:pos_apotek/core/database/app_database.dart';
import 'package:pos_apotek/core/security/pin_hasher.dart';

/// Database SQLite di memori untuk pengujian.
AppDatabase memoryDatabase() => AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );

/// Hasher cepat untuk pengujian (tanpa isolate, iterasi sedikit).
const fastHasher = PinHasher(iterations: 2, useIsolate: false);

/// Jam yang bisa dimajukan secara manual.
class FakeClock {
  FakeClock([DateTime? start]) : now = start ?? DateTime(2026, 11, 25, 8);

  DateTime now;

  DateTime call() => now;

  void advance(Duration d) => now = now.add(d);
}
