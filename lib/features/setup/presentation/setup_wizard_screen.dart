import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../backup/presentation/backup_screen.dart';

import '../../../core/widgets/common.dart';
import '../../../core/widgets/pin_pad.dart';
import '../../../core/widgets/recovery_code_view.dart';
import '../../auth/application/session_controller.dart';
import '../../settings/data/settings_repository.dart';
import '../../settings/presentation/store_profile_fields.dart';
import '../data/setup_service.dart';

enum _Step { welcome, store, ownerName, ownerPin, recovery }

/// Wizard yang muncul sekali saat aplikasi pertama kali dibuka.
class SetupWizardScreen extends ConsumerStatefulWidget {
  const SetupWizardScreen({super.key});

  @override
  ConsumerState<SetupWizardScreen> createState() => _SetupWizardScreenState();
}

class _SetupWizardScreenState extends ConsumerState<SetupWizardScreen> {
  _Step _step = _Step.welcome;
  final _storeFormKey = GlobalKey<FormState>();
  final _ownerFormKey = GlobalKey<FormState>();
  final _store = StoreProfileControllers();
  final _ownerName = TextEditingController();
  SetupResult? _result;

  @override
  void dispose() {
    _store.dispose();
    _ownerName.dispose();
    super.dispose();
  }

  void _go(_Step step) => setState(() => _step = step);

  Future<void> _finishSetup(String pin) async {
    final result = await ref.read(setupServiceProvider).complete(
          store: _store.toProfile(),
          ownerName: _ownerName.text,
          ownerPin: pin,
        );
    setState(() {
      _result = result;
      _step = _Step.recovery;
    });
  }

  void _enterApp() {
    ref.read(sessionProvider.notifier).signIn(_result!.owner);
    ref.invalidate(setupCompletedProvider);
  }

  bool get _canGoBack =>
      _step == _Step.store || _step == _Step.ownerName || _step == _Step.ownerPin;

  void _back() => _go(_Step.values[_step.index - 1]);

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _canGoBack) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: _canGoBack
              ? IconButton(
                  tooltip: 'Kembali',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _back,
                )
              : null,
          title: _step == _Step.welcome
              ? null
              : Text('Langkah ${_stepNumber()} dari 3'),
          bottom: _step == _Step.welcome
              ? null
              : PreferredSize(
                  preferredSize: const Size.fromHeight(4),
                  child: LinearProgressIndicator(value: _stepNumber() / 3),
                ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: ContentWidth(child: _body(context)),
          ),
        ),
      ),
    );
  }

  int _stepNumber() => switch (_step) {
        _Step.welcome || _Step.store => 1,
        _Step.ownerName || _Step.ownerPin => 2,
        _Step.recovery => 3,
      };

  Widget _body(BuildContext context) {
    final theme = Theme.of(context);
    switch (_step) {
      case _Step.welcome:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 32),
            CircleAvatar(
              radius: 48,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Icon(
                Icons.local_pharmacy_rounded,
                size: 52,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Selamat datang di POS Apotek',
              style: theme.textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Kita siapkan aplikasinya dalam 3 langkah singkat:\n'
              'data apotek, akun pemilik, dan kode pemulihan.',
              style: theme.textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            FilledButton(
              onPressed: () => _go(_Step.store),
              child: const Text('Mulai'),
            ),
            const SizedBox(height: 32),
            Text(
              'Pindah dari HP lama atau sudah punya file backup?',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            TextButton.icon(
              onPressed: () => pickAndRestore(context, ref, fromSetup: true),
              icon: const Icon(Icons.restore_rounded),
              label: const Text('Pulihkan dari backup'),
            ),
          ],
        );

      case _Step.store:
        return Form(
          key: _storeFormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Data Apotek', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 4),
              const Text('Tampil di aplikasi dan di kepala struk.'),
              const SizedBox(height: 20),
              StoreProfileFields(controllers: _store),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () {
                  if (_storeFormKey.currentState!.validate()) {
                    _go(_Step.ownerName);
                  }
                },
                child: const Text('Lanjut'),
              ),
            ],
          ),
        );

      case _Step.ownerName:
        return Form(
          key: _ownerFormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Akun Pemilik', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 4),
              const Text(
                'Pemilik bisa melihat laporan & laba, mengubah harga, '
                'dan menambah akun kasir.',
              ),
              const SizedBox(height: 20),
              TextFormField(
                key: const Key('owner-name'),
                controller: _ownerName,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nama pemilik *',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Nama wajib diisi' : null,
                onFieldSubmitted: (_) => _submitOwnerName(),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _submitOwnerName,
                child: const Text('Lanjut'),
              ),
            ],
          ),
        );

      case _Step.ownerPin:
        return PinSetupFlow(
          title: 'Buat PIN untuk ${_ownerName.text.trim()}',
          onPinChosen: _finishSetup,
        );

      case _Step.recovery:
        return RecoveryCodeView(
          code: _result!.recoveryCode,
          doneLabel: 'Selesai, masuk ke aplikasi',
          onDone: _enterApp,
          footer: Column(
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.group_add_outlined),
                  title: const Text('Saran: buat Pemilik kedua'),
                  subtitle: const Text(
                    'Jika suatu saat PIN lupa dan kode ini hilang, Pemilik kedua '
                    'bisa mengatur ulang PIN Anda. Tambahkan di Pengaturan → '
                    'Pengguna.',
                  ),
                  iconColor: theme.colorScheme.primary,
                ),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('Pengaturan lainnya'),
                  subtitle: const Text(
                    'QRIS, printer, dan notifikasi Telegram bisa diatur kapan '
                    'saja di menu Pengaturan.',
                  ),
                  iconColor: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        );
    }
  }

  void _submitOwnerName() {
    if (_ownerFormKey.currentState!.validate()) _go(_Step.ownerPin);
  }
}
