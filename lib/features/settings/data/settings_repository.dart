import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/clock.dart';
import '../../../core/database/app_database.dart';

/// Kunci-kunci di tabel `app_settings`.
abstract final class SettingKeys {
  static const setupCompleted = 'app.setup_completed';

  static const storeName = 'store.name';
  static const storeAddress = 'store.address';
  static const storePhone = 'store.phone';
  static const receiptFooter = 'receipt.footer';

  static const recoveryHash = 'auth.recovery_hash';
  static const recoverySalt = 'auth.recovery_salt';
}

/// Identitas apotek yang tampil di aplikasi dan kepala struk.
class StoreProfile {
  const StoreProfile({
    required this.name,
    this.address = '',
    this.phone = '',
    this.receiptFooter = defaultReceiptFooter,
  });

  static const defaultReceiptFooter = 'Terima kasih, semoga lekas sembuh.';

  final String name;
  final String address;
  final String phone;
  final String receiptFooter;

  StoreProfile copyWith({
    String? name,
    String? address,
    String? phone,
    String? receiptFooter,
  }) =>
      StoreProfile(
        name: name ?? this.name,
        address: address ?? this.address,
        phone: phone ?? this.phone,
        receiptFooter: receiptFooter ?? this.receiptFooter,
      );

  static StoreProfile fromMap(Map<String, String> map) => StoreProfile(
        name: map[SettingKeys.storeName] ?? '',
        address: map[SettingKeys.storeAddress] ?? '',
        phone: map[SettingKeys.storePhone] ?? '',
        receiptFooter:
            map[SettingKeys.receiptFooter] ?? defaultReceiptFooter,
      );

  Map<String, String> toMap() => {
        SettingKeys.storeName: name.trim(),
        SettingKeys.storeAddress: address.trim(),
        SettingKeys.storePhone: phone.trim(),
        SettingKeys.receiptFooter: receiptFooter.trim(),
      };
}

class SettingsRepository {
  SettingsRepository(this._db, this._now);

  final AppDatabase _db;
  final Clock _now;

  Future<String?> get(String key) async {
    final row = await (_db.select(_db.appSettings)
          ..where((s) => s.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> set(String key, String value) => setAll({key: value});

  Future<void> setAll(Map<String, String> values) async {
    final now = _now();
    await _db.batch((b) {
      b.insertAllOnConflictUpdate(
        _db.appSettings,
        [
          for (final e in values.entries)
            AppSettingsCompanion.insert(
              key: e.key,
              value: e.value,
              updatedAt: now,
            ),
        ],
      );
    });
  }

  Stream<Map<String, String>> watchAll() =>
      _db.select(_db.appSettings).watch().map(
            (rows) => {for (final r in rows) r.key: r.value},
          );

  Future<bool> isSetupCompleted() async =>
      await get(SettingKeys.setupCompleted) == 'true';

  Future<void> markSetupCompleted() => set(SettingKeys.setupCompleted, 'true');

  Stream<StoreProfile> watchStoreProfile() =>
      watchAll().map(StoreProfile.fromMap);

  Future<void> saveStoreProfile(StoreProfile profile) {
    if (profile.name.trim().isEmpty) {
      throw ArgumentError('Nama apotek wajib diisi');
    }
    return setAll(profile.toMap());
  }
}

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(
    ref.watch(databaseProvider),
    ref.watch(clockProvider),
  ),
);

final storeProfileProvider = StreamProvider<StoreProfile>(
  (ref) => ref.watch(settingsRepositoryProvider).watchStoreProfile(),
);

/// Apakah wizard setup awal sudah selesai.
final setupCompletedProvider = FutureProvider<bool>(
  (ref) => ref.watch(settingsRepositoryProvider).isSetupCompleted(),
);
