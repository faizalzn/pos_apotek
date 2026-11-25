import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'app.dart';
import 'core/database/app_database.dart';

void main() {
  runApp(const AppRoot());
}

/// Pemilik [ProviderContainer] aplikasi. Bisa memulai ulang seluruh aplikasi
/// (database ditutup lalu dibuka lagi) — dipakai setelah memulihkan backup.
class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  ProviderContainer _container = ProviderContainer();
  bool _restarting = false;

  Future<void> _restart(Future<void> Function() whileClosed) async {
    setState(() => _restarting = true);
    await WidgetsBinding.instance.endOfFrame;
    final db = _container.read(databaseProvider);
    _container.dispose();
    await db.close();
    try {
      await whileClosed();
    } finally {
      if (mounted) {
        setState(() {
          _container = ProviderContainer();
          _restarting = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _container.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_restarting) {
      return const ColoredBox(
        color: Colors.white,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return AppRestart(
      restart: _restart,
      child: UncontrolledProviderScope(
        key: ObjectKey(_container),
        container: _container,
        child: const PosApotekApp(),
      ),
    );
  }
}
