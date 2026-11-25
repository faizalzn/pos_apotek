import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../auth/data/recovery_code_service.dart';
import '../../auth/data/user_repository.dart';
import '../../settings/data/settings_repository.dart';

class SetupResult {
  const SetupResult({required this.owner, required this.recoveryCode});
  final AppUser owner;

  /// Kode pemulihan dalam format tampilan (`ABCD-EFGH`). Hanya ada di sini;
  /// database hanya menyimpan hash-nya.
  final String recoveryCode;
}

/// Menyelesaikan wizard setup awal dalam satu transaksi.
class SetupService {
  SetupService(this._db, this._settings, this._users, this._recovery);

  final AppDatabase _db;
  final SettingsRepository _settings;
  final UserRepository _users;
  final RecoveryCodeService _recovery;

  Future<SetupResult> complete({
    required StoreProfile store,
    required String ownerName,
    required String ownerPin,
  }) {
    return _db.transaction(() async {
      if (await _settings.isSetupCompleted()) {
        throw const UserRuleException('Aplikasi sudah pernah disiapkan');
      }
      await _settings.saveStoreProfile(store);
      final owner = await _users.create(
        name: ownerName,
        role: UserRole.owner,
        pin: ownerPin,
      );
      final code = await _recovery.issueNew();
      await _settings.markSetupCompleted();
      return SetupResult(owner: owner, recoveryCode: code);
    });
  }
}

final setupServiceProvider = Provider<SetupService>(
  (ref) => SetupService(
    ref.watch(databaseProvider),
    ref.watch(settingsRepositoryProvider),
    ref.watch(userRepositoryProvider),
    ref.watch(recoveryCodeServiceProvider),
  ),
);
