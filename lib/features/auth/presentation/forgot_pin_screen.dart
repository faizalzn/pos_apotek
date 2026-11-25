import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/database/app_database.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/pin_pad.dart';
import '../../../core/widgets/recovery_code_view.dart';
import '../data/recovery_code_service.dart';
import 'rescue_screen.dart';

/// Pemilik membuat PIN baru memakai kode pemulihan.
class ForgotPinScreen extends ConsumerStatefulWidget {
  const ForgotPinScreen({super.key, required this.owner});

  final AppUser owner;

  @override
  ConsumerState<ForgotPinScreen> createState() => _ForgotPinScreenState();
}

class _ForgotPinScreenState extends ConsumerState<ForgotPinScreen> {
  final _codeController = TextEditingController();
  String? _verifiedCode;
  String? _newRecoveryCode;
  String? _codeError;
  bool _checking = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    setState(() {
      _checking = true;
      _codeError = null;
    });
    final ok = await ref
        .read(recoveryCodeServiceProvider)
        .verify(_codeController.text);
    if (!mounted) return;
    setState(() {
      _checking = false;
      if (ok) {
        _verifiedCode = _codeController.text;
      } else {
        _codeError = 'Kode pemulihan tidak cocok';
      }
    });
  }

  Future<void> _setPin(String pin) async {
    final newCode = await ref.read(recoveryCodeServiceProvider).resetOwnerPin(
          code: _verifiedCode!,
          ownerId: widget.owner.id,
          newPin: pin,
        );
    if (!mounted) return;
    if (newCode == null) {
      setState(() => _verifiedCode = null);
      showMessage(context, 'Kode pemulihan tidak berlaku lagi', error: true);
      return;
    }
    setState(() => _newRecoveryCode = newCode);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lupa PIN')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ContentWidth(child: _body(context)),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_newRecoveryCode != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'PIN baru tersimpan. Kode pemulihan lama sudah tidak berlaku — '
            'ini kode pemulihan yang baru:',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          RecoveryCodeView(
            code: _newRecoveryCode!,
            doneLabel: 'Kembali ke halaman masuk',
            onDone: () => Navigator.pop(context),
          ),
        ],
      );
    }
    if (_verifiedCode != null) {
      return PinSetupFlow(
        title: 'Buat PIN baru',
        subtitle: 'untuk ${widget.owner.name}',
        onPinChosen: _setPin,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Masukkan kode pemulihan yang dicatat saat aplikasi pertama kali '
          'disiapkan (contoh: ABCD-EFGH).',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 20),
        TextField(
          key: const Key('recovery-code'),
          controller: _codeController,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          style: const TextStyle(fontSize: 22, letterSpacing: 3),
          decoration: InputDecoration(
            labelText: 'Kode pemulihan',
            errorText: _codeError,
            prefixIcon: const Icon(Icons.key_outlined),
          ),
          onSubmitted: (_) => _verify(),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _checking ? null : _verify,
          child: _checking
              ? const SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              : const Text('Lanjut'),
        ),
        const SizedBox(height: 32),
        const Divider(),
        TextButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => RescueScreen(owner: widget.owner),
            ),
          ),
          icon: const Icon(Icons.support_agent_rounded),
          label: const Text('Kode pemulihan hilang?'),
        ),
      ],
    );
  }
}
