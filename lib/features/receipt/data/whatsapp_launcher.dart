import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../settings/data/settings_repository.dart';

enum WhatsAppApp {
  whatsapp('WhatsApp', 'com.whatsapp'),
  business('WhatsApp Business', 'com.whatsapp.w4b');

  const WhatsAppApp(this.label, this.package);
  final String label;
  final String package;

  static WhatsAppApp? byName(String? name) =>
      values.where((a) => a.name == name).firstOrNull;
}

/// Membuka WhatsApp tertentu (bukan sekadar aplikasi bawaan untuk tautan wa.me).
class WhatsAppLauncher {
  WhatsAppLauncher(this._settings);

  final SettingsRepository _settings;

  /// `whatsapp` / `business`; kosong = tanya setiap kali.
  static const preferenceKey = 'receipt.whatsapp_app';

  Uri _uri(String number, String text) => Uri(
    scheme: 'whatsapp',
    host: 'send',
    queryParameters: {if (number.isNotEmpty) 'phone': number, 'text': text},
  );

  /// Aplikasi WhatsApp yang terpasang di HP ini.
  Future<List<WhatsAppApp>> installed() async {
    if (!Platform.isAndroid) return const [];
    return [
      for (final app in WhatsAppApp.values)
        if (await AndroidIntent(
              action: 'action_view',
              data: 'whatsapp://send?text=',
              package: app.package,
            ).canResolveActivity() ??
            false)
          app,
    ];
  }

  Future<WhatsAppApp?> preference() async =>
      WhatsAppApp.byName(await _settings.get(preferenceKey));

  Future<void> setPreference(WhatsAppApp? app) =>
      _settings.set(preferenceKey, app?.name ?? '');

  /// [app] `null` → tautan wa.me biasa (dipilih oleh Android).
  Future<bool> open({
    required WhatsAppApp? app,
    required String number,
    required String text,
  }) async {
    if (app != null && Platform.isAndroid) {
      await AndroidIntent(
        action: 'action_view',
        data: _uri(number, text).toString(),
        package: app.package,
      ).launch();
      return true;
    }
    final uri = Uri.https('wa.me', number.isEmpty ? '/' : '/$number', {
      'text': text,
    });
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

final whatsAppLauncherProvider = Provider<WhatsAppLauncher>(
  (ref) => WhatsAppLauncher(ref.watch(settingsRepositoryProvider)),
);
