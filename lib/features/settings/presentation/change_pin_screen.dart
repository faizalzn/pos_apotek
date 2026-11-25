import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/common.dart';
import '../../../core/widgets/pin_pad.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/data/user_repository.dart';

/// Pengguna yang sedang masuk mengganti PIN-nya sendiri.
class ChangePinScreen extends ConsumerStatefulWidget {
  const ChangePinScreen({super.key});

  @override
  ConsumerState<ChangePinScreen> createState() => _ChangePinScreenState();
}

class _ChangePinScreenState extends ConsumerState<ChangePinScreen> {
  bool _verified = false;
  String? _error;

  Future<void> _verifyCurrent(String pin) async {
    final user = ref.read(sessionProvider)!;
    final result = await ref.read(userRepositoryProvider).checkPin(user.id, pin);
    if (!mounted) return;
    setState(() {
      switch (result) {
        case PinAccepted():
          _verified = true;
          _error = null;
        case PinRejected(:final attemptsLeft):
          _error = 'PIN salah. Sisa percobaan: $attemptsLeft';
        case PinLocked(:final remaining):
          _error =
              'Terlalu banyak salah. Coba lagi dalam ${formatWait(remaining)}.';
      }
    });
  }

  Future<void> _setNew(String pin) async {
    final user = ref.read(sessionProvider)!;
    await ref.read(userRepositoryProvider).setPin(user.id, pin);
    if (!mounted) return;
    showMessage(context, 'PIN berhasil diganti');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ganti PIN')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: _verified
                ? PinSetupFlow(title: 'Buat PIN baru', onPinChosen: _setNew)
                : PinPad(
                    title: 'Masukkan PIN saat ini',
                    errorText: _error,
                    onCompleted: _verifyCurrent,
                  ),
          ),
        ),
      ),
    );
  }
}
