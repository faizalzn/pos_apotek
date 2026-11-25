import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'core/database/app_database.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/application/session_controller.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/home/presentation/home_screen.dart';
import 'features/settings/data/settings_repository.dart';
import 'features/setup/presentation/setup_wizard_screen.dart';

final _navigatorKey = GlobalKey<NavigatorState>();

class PosApotekApp extends ConsumerWidget {
  const PosApotekApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Saat keluar (logout), tutup semua layar yang sedang terbuka.
    ref.listen<AppUser?>(sessionProvider, (previous, next) {
      if (next == null) {
        _navigatorKey.currentState?.popUntil((route) => route.isFirst);
      }
    });

    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'POS Apotek',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      locale: const Locale('id'),
      supportedLocales: const [Locale('id'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const AppGate(),
    );
  }
}

/// Menentukan layar awal: wizard setup → login → beranda.
class AppGate extends ConsumerWidget {
  const AppGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setupCompleted = ref.watch(setupCompletedProvider);
    final user = ref.watch(sessionProvider);

    return setupCompleted.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 12),
                Text('Gagal membuka data: $error', textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => ref.invalidate(setupCompletedProvider),
                  child: const Text('Coba lagi'),
                ),
              ],
            ),
          ),
        ),
      ),
      data: (done) {
        if (!done) return const SetupWizardScreen();
        if (user == null) return const LoginScreen();
        return const HomeScreen();
      },
    );
  }
}
