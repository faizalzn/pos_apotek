import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/clock.dart';
import '../../../core/config.dart';
import '../../../core/database/app_database.dart';
import '../../../core/security/rescue_code.dart';
import '../../settings/data/settings_repository.dart';
import 'recovery_code_service.dart';
import 'user_repository.dart';

/// Jalan terakhir bagi Pemilik yang lupa PIN **dan** kehilangan kode
/// pemulihan: kode darurat yang ditandatangani developer (ADR-0009).
class RescueService {
  RescueService(
    this._settings,
    this._users,
    this._recovery,
    this._config,
    this._now,
  );

  final SettingsRepository _settings;
  final UserRepository _users;
  final RecoveryCodeService _recovery;
  final AppConfig _config;
  final Clock _now;

  /// Lama kode tantangan berlaku.
  static const validity = Duration(hours: 24);

  static const _challengeKey = 'rescue.challenge';
  static const _expiresKey = 'rescue.expires_at';

  bool get enabled => _config.rescueEnabled;

  /// Kode tantangan yang sedang berlaku. Bila belum ada atau sudah
  /// kedaluwarsa, dibuat yang baru — sehingga menutup aplikasi sambil
  /// menunggu balasan developer tidak mengganti kodenya.
  Future<String> currentChallenge() async {
    final existing = await _settings.get(_challengeKey);
    final expires = DateTime.tryParse(await _settings.get(_expiresKey) ?? '');
    if (existing != null && expires != null && expires.isAfter(_now())) {
      return existing;
    }
    final challenge = RescueCode.newChallenge();
    await _settings.setAll({
      _challengeKey: challenge,
      _expiresKey: _now().add(validity).toIso8601String(),
    });
    return challenge;
  }

  Future<bool> verifyReply(String replyText) async {
    if (!enabled) return false;
    final challenge = await _settings.get(_challengeKey);
    final expires = DateTime.tryParse(await _settings.get(_expiresKey) ?? '');
    if (challenge == null || expires == null || !expires.isAfter(_now())) {
      return false;
    }
    return RescueCode.verify(
      challenge: challenge,
      reply: replyText,
      publicKey: _config.rescuePublicKey,
    );
  }

  /// Mengatur PIN baru untuk Pemilik. Kode tantangan langsung hangus
  /// (sekali pakai) dan kode pemulihan baru dibuat.
  ///
  /// Mengembalikan kode pemulihan baru, atau `null` bila balasan tidak sah.
  Future<String?> resetOwnerPin({
    required String replyText,
    required String ownerId,
    required String newPin,
  }) async {
    if (!await verifyReply(replyText)) return null;
    final owner = await _users.byId(ownerId);
    if (owner == null || owner.role != UserRole.owner) {
      throw const UserRuleException('Kode darurat hanya untuk Pemilik');
    }
    await _users.setPin(ownerId, newPin);
    await _settings.setAll({
      _challengeKey: '',
      _expiresKey: _now().toIso8601String(),
    });
    return _recovery.issueNew();
  }

  /// Teks pesan WhatsApp yang dikirim Pemilik ke developer.
  static String requestMessage({
    required String storeName,
    required String challenge,
  }) =>
      'Halo, saya Pemilik $storeName. Saya lupa PIN dan kode pemulihan '
      'POS Apotek hilang. Mohon kode darurat.\n\n'
      'Kode tantangan: $challenge';

  /// Tautan wa.me ke developer, atau `null` bila nomor belum diatur.
  Uri? whatsAppLink(String message) {
    final number = _config.developerWhatsAppNormalized;
    if (number.isEmpty) return null;
    return Uri.https('wa.me', '/$number', {'text': message});
  }
}

final rescueServiceProvider = Provider<RescueService>(
  (ref) => RescueService(
    ref.watch(settingsRepositoryProvider),
    ref.watch(userRepositoryProvider),
    ref.watch(recoveryCodeServiceProvider),
    ref.watch(appConfigProvider),
    ref.watch(clockProvider),
  ),
);
