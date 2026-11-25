import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/database/app_database.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/pin_pad.dart';
import '../../../core/widgets/recovery_code_view.dart';
import '../../settings/data/settings_repository.dart';
import '../data/rescue_service.dart';

/// Jalan terakhir: Pemilik lupa PIN dan kode pemulihan hilang.
class RescueScreen extends ConsumerStatefulWidget {
  const RescueScreen({super.key, required this.owner});

  final AppUser owner;

  @override
  ConsumerState<RescueScreen> createState() => _RescueScreenState();
}

class _RescueScreenState extends ConsumerState<RescueScreen> {
  final _replyController = TextEditingController();
  late final Future<String> _challenge;
  String? _verifiedReply;
  String? _newRecoveryCode;
  String? _error;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _challenge = ref.read(rescueServiceProvider).currentChallenge();
  }

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  Future<void> _sendWhatsApp(String challenge) async {
    final service = ref.read(rescueServiceProvider);
    final storeName = ref.read(storeProfileProvider).value?.name ?? 'apotek';
    final link = service.whatsAppLink(
      RescueService.requestMessage(storeName: storeName, challenge: challenge),
    );
    if (link == null) return;
    final opened = await launchUrl(link, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      showMessage(context, 'WhatsApp tidak bisa dibuka', error: true);
    }
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (text.isEmpty) {
      if (mounted) showMessage(context, 'Belum ada teks yang disalin');
      return;
    }
    _replyController.text = text;
    await _verify();
  }

  Future<void> _verify() async {
    setState(() {
      _checking = true;
      _error = null;
    });
    final text = _replyController.text;
    final ok = await ref.read(rescueServiceProvider).verifyReply(text);
    if (!mounted) return;
    setState(() {
      _checking = false;
      if (ok) {
        _verifiedReply = text;
      } else {
        _error = 'Kode darurat tidak cocok. Pastikan yang disalin adalah '
            'balasan untuk kode tantangan di atas.';
      }
    });
  }

  Future<void> _setPin(String pin) async {
    final code = await ref.read(rescueServiceProvider).resetOwnerPin(
          replyText: _verifiedReply!,
          ownerId: widget.owner.id,
          newPin: pin,
        );
    if (!mounted) return;
    if (code == null) {
      setState(() => _verifiedReply = null);
      showMessage(context, 'Kode darurat sudah tidak berlaku', error: true);
      return;
    }
    setState(() => _newRecoveryCode = code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bantuan Darurat')),
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
            'PIN baru tersimpan. Karena kode pemulihan lama hilang, '
            'ini kode pemulihan yang baru — kali ini simpan baik-baik:',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          RecoveryCodeView(
            code: _newRecoveryCode!,
            doneLabel: 'Kembali ke halaman masuk',
            onDone: () => Navigator.of(context).popUntil((r) => r.isFirst),
          ),
        ],
      );
    }
    if (_verifiedReply != null) {
      return PinSetupFlow(
        title: 'Buat PIN baru',
        subtitle: 'untuk ${widget.owner.name}',
        onPinChosen: _setPin,
      );
    }

    final theme = Theme.of(context);
    final service = ref.watch(rescueServiceProvider);
    if (!service.enabled) {
      return const _Info(
        icon: Icons.support_agent_rounded,
        text: 'Bantuan darurat belum disiapkan di aplikasi ini.\n\n'
            'Hubungi developer aplikasi, atau minta Pemilik lain mengatur '
            'ulang PIN Anda di Pengaturan → Pengguna.',
      );
    }

    return FutureBuilder<String>(
      future: _challenge,
      builder: (context, snapshot) {
        final challenge = snapshot.data;
        if (challenge == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final canWhatsApp = service.whatsAppLink('') != null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Jangan khawatir, data apotek tetap aman. '
              'Ikuti 2 langkah berikut:',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 20),
            _StepTitle(number: 1, text: 'Kirim kode ini ke developer'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: SelectableText(
                challenge,
                key: const Key('rescue-challenge'),
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (canWhatsApp)
              FilledButton.icon(
                onPressed: () => _sendWhatsApp(challenge),
                icon: const Icon(Icons.chat_rounded),
                label: const Text('Kirim lewat WhatsApp'),
              ),
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: challenge));
                showMessage(context, 'Kode tantangan disalin');
              },
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Salin kode'),
            ),
            const SizedBox(height: 24),
            _StepTitle(number: 2, text: 'Tempel balasan dari developer'),
            const SizedBox(height: 8),
            Text(
              'Di WhatsApp, tekan lama pesan balasan → Salin. '
              'Lalu kembali ke sini dan tekan tombol di bawah.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: _checking ? null : _paste,
              icon: const Icon(Icons.content_paste_rounded),
              label: const Text('Tempel kode'),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('rescue-reply'),
              controller: _replyController,
              minLines: 2,
              maxLines: 4,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'atau ketik kode balasan di sini',
                errorText: _error,
                errorMaxLines: 3,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _checking ? null : _verify,
              child: const Text('Periksa kode'),
            ),
            const SizedBox(height: 16),
            Text(
              'Kode tantangan berlaku 24 jam. Aplikasi boleh ditutup sambil '
              'menunggu balasan — kodenya tidak berubah.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        );
      },
    );
  }
}

class _StepTitle extends StatelessWidget {
  const _StepTitle({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          CircleAvatar(radius: 14, child: Text('$number')),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.titleMedium),
          ),
        ],
      );
}

class _Info extends StatelessWidget {
  const _Info({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          const SizedBox(height: 24),
          Icon(icon, size: 56, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            text,
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ],
      );
}
