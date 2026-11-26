import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Konfigurasi yang disisipkan saat build dari `secrets.json`
/// (`--dart-define-from-file=secrets.json`). Lihat ADR-0008.
class AppConfig {
  const AppConfig({
    this.rescuePublicKey = '',
    this.developerWhatsApp = '',
    this.telegramBotToken = '',
    this.telegramBotUsername = '',
  });

  const AppConfig.fromEnvironment()
      : rescuePublicKey = const String.fromEnvironment('RESCUE_PUBLIC_KEY'),
        developerWhatsApp =
            const String.fromEnvironment('DEVELOPER_WHATSAPP'),
        telegramBotToken = const String.fromEnvironment('TELEGRAM_BOT_TOKEN'),
        telegramBotUsername =
            const String.fromEnvironment('TELEGRAM_BOT_USERNAME');

  /// Kunci publik Ed25519 (base64) untuk memeriksa kode darurat developer.
  final String rescuePublicKey;

  /// Nomor WhatsApp developer dalam format internasional tanpa `+`,
  /// mis. `6281234567890`.
  final String developerWhatsApp;

  /// Token bot Telegram dari @BotFather (ADR-0003).
  final String telegramBotToken;

  /// Username bot tanpa `@`, untuk tautan `t.me/<bot>?start=…`.
  final String telegramBotUsername;

  bool get rescueEnabled => rescuePublicKey.isNotEmpty;

  bool get telegramEnabled =>
      telegramBotToken.isNotEmpty && telegramBotUsername.isNotEmpty;

  /// Nomor WhatsApp yang sudah dibersihkan dari spasi, `+`, dan `-`;
  /// awalan `0` diganti `62`.
  String get developerWhatsAppNormalized {
    final digits = developerWhatsApp.replaceAll(RegExp(r'\D'), '');
    return digits.startsWith('0') ? '62${digits.substring(1)}' : digits;
  }
}

final appConfigProvider =
    Provider<AppConfig>((ref) => const AppConfig.fromEnvironment());
