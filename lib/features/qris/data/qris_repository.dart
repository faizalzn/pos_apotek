import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../settings/data/settings_repository.dart';
import 'qris.dart';

/// QRIS statis milik apotek, disimpan di pengaturan (data privat, ADR-0008).
class QrisRepository {
  QrisRepository(this._db, this._settings);

  final AppDatabase _db;
  final SettingsRepository _settings;

  static const key = 'qris.payload';

  Stream<Qris?> watch() =>
      (_db.select(_db.appSettings)..where((s) => s.key.equals(key)))
          .watchSingleOrNull()
          .map((row) => _parse(row?.value));

  Future<Qris?> get() async => _parse(await _settings.get(key));

  static Qris? _parse(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      return Qris.parse(payload);
    } on QrisException {
      return null;
    }
  }

  /// Memeriksa lalu menyimpan. Melempar [QrisException] bila bukan QRIS.
  Future<Qris> save(String raw) async {
    final qris = Qris.parse(raw);
    await _settings.set(key, qris.payload);
    return qris;
  }

  Future<void> clear() => _settings.set(key, '');
}

final qrisRepositoryProvider = Provider<QrisRepository>(
  (ref) => QrisRepository(
    ref.watch(databaseProvider),
    ref.watch(settingsRepositoryProvider),
  ),
);

final qrisProvider = StreamProvider<Qris?>(
  (ref) => ref.watch(qrisRepositoryProvider).watch(),
);
