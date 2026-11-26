import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/widgets/common.dart';
import '../data/telegram_api.dart';
import '../data/telegram_service.dart';

/// Pengaturan notifikasi Telegram ke HP Pemilik (khusus Pemilik).
class TelegramSettingsScreen extends ConsumerWidget {
  const TelegramSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(telegramStatusProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Notifikasi Telegram')),
      body: switch (status) {
        AsyncData(:final value) => ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            ContentWidth(
              maxWidth: 600,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: !value.enabled
                    ? const [_TokenForm()]
                    : [
                        if (value.linked)
                          _Linked(status: value)
                        else
                          const _NotLinked(),
                        _BotInfo(status: value),
                      ],
              ),
            ),
          ],
        ),
        AsyncError(:final error) => Center(child: Text('$error')),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

/// Langkah 1: Pemilik membuat bot di @BotFather lalu menempel tokennya.
class _TokenForm extends ConsumerStatefulWidget {
  const _TokenForm({this.onDone});

  /// Dipanggil setelah token tersimpan (mis. menutup dialog "Ganti bot").
  final VoidCallback? onDone;

  @override
  ConsumerState<_TokenForm> createState() => _TokenFormState();
}

class _TokenFormState extends ConsumerState<_TokenForm> {
  final _token = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text case final t? when t.isNotEmpty) {
      setState(() => _token.text = t.trim());
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final username = await ref
          .read(telegramServiceProvider)
          .saveToken(_token.text);
      if (!mounted) return;
      showMessage(context, 'Bot @$username siap dipakai');
      widget.onDone?.call();
    } on TelegramException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.onDone == null) ...[
            Icon(
              Icons.smart_toy_outlined,
              size: 56,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              'Siapkan bot Telegram (sekali saja)',
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Bot inilah yang nanti mengirim laporan ke Telegram Pemilik. '
              'Gratis, sekitar 2 menit.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
          ],
          const _Step(1, 'Buka Telegram, cari @BotFather, tekan MULAI/START.'),
          const _Step(2, 'Kirim pesan /newbot.'),
          const _Step(
            3,
            'Isi nama bot (bebas, mis. "Apotek Sehat"), lalu username yang '
            'berakhiran "bot" (mis. apotek_sehat_bot).',
          ),
          const _Step(
            4,
            'BotFather membalas dengan token, bentuknya seperti '
            '123456789:AAHk3…. Salin token itu, lalu tempel di bawah.',
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => launchUrl(
              Uri.https('t.me', '/BotFather'),
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(Icons.open_in_new),
            label: const Text('Buka @BotFather'),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('telegram-token'),
            controller: _token,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.visiblePassword,
            onChanged: (_) => setState(() => _error = null),
            decoration: InputDecoration(
              labelText: 'Token bot',
              hintText: '123456789:AAH…',
              errorText: _error,
              errorMaxLines: 3,
              suffixIcon: IconButton(
                tooltip: 'Tempel',
                onPressed: _paste,
                icon: const Icon(Icons.content_paste),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Jangan bagikan token ini ke siapa pun. Token hanya disimpan di HP ini '
            '(dan ikut di file backup).',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('telegram-save-token'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
            ),
            onPressed: _saving || _token.text.trim().isEmpty ? null : _save,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: const Text('Simpan & periksa'),
          ),
        ],
      ),
    );
  }
}

/// Bot yang dipakai + ganti/hapus.
class _BotInfo extends ConsumerWidget {
  const _BotInfo({required this.status});

  final TelegramStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.read(telegramServiceProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 32),
        ListTile(
          leading: const Icon(Icons.smart_toy_outlined),
          title: Text('Bot @${status.botUsername}'),
          subtitle: Text(
            status.tokenFromBuild
                ? 'Dipasang oleh pembuat aplikasi'
                : 'Ketuk untuk mengganti token bot',
          ),
          onTap: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            builder: (sheet) => Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(sheet).bottom,
              ),
              child: SingleChildScrollView(
                child: _TokenForm(onDone: () => Navigator.pop(sheet)),
              ),
            ),
          ),
        ),
        if (!status.tokenFromBuild)
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Hapus token bot'),
            onTap: () async {
              final ok = await confirm(
                context,
                title: 'Hapus token bot?',
                message:
                    'Notifikasi berhenti dan sambungan Telegram diputus. '
                    'Pesan yang belum terkirim dihapus.',
                confirmLabel: 'Hapus',
              );
              if (ok) await service.removeToken();
            },
          ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _NotLinked extends ConsumerStatefulWidget {
  const _NotLinked();

  @override
  ConsumerState<_NotLinked> createState() => _NotLinkedState();
}

class _NotLinkedState extends ConsumerState<_NotLinked> {
  bool _waiting = false;
  bool _cancelled = false;

  @override
  void dispose() {
    _cancelled = true;
    super.dispose();
  }

  /// [share] = kirim tautan ke HP lain (mis. lewat WhatsApp ke Pemilik).
  Future<void> _connect({required bool share}) async {
    final service = ref.read(telegramServiceProvider);
    final code = service.newLinkCode();
    final link = await service.linkUri(code);
    setState(() {
      _waiting = true;
      _cancelled = false;
    });
    try {
      if (share) {
        await SharePlus.instance.share(
          ShareParams(
            text:
                'Buka tautan ini di HP Pemilik, lalu tekan MULAI/START '
                'untuk menerima notifikasi apotek:\n$link',
          ),
        );
      } else {
        final opened = await launchUrl(
          link,
          mode: LaunchMode.externalApplication,
        );
        if (!opened) {
          throw const TelegramException('Telegram tidak bisa dibuka');
        }
      }
      final name = await service.waitForLink(
        code,
        // Lewat HP lain butuh waktu lebih lama (kirim, buka, tekan START).
        timeout: Duration(minutes: share ? 10 : 3),
        cancelled: () => _cancelled,
      );
      if (!mounted) return;
      if (name != null) {
        showMessage(context, 'Terhubung ke Telegram $name');
      } else if (!_cancelled) {
        showMessage(
          context,
          'Belum ada tanda dari Telegram. Pastikan menekan tombol MULAI/START, '
          'lalu coba lagi.',
          error: true,
        );
      }
    } on TelegramException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _waiting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.send_rounded, size: 56, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text(
            'Pantau apotek dari HP Pemilik',
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'Setiap transaksi, pembatalan, tutup shift, dan ringkasan harian '
            'dikirim ke Telegram Pemilik. Bila internet mati, pesan disimpan '
            'dan dikirim otomatis saat internet kembali.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          const _Step(1, 'Pastikan Telegram terpasang di HP Pemilik.'),
          const _Step(
            2,
            'Bila ini HP Pemilik: tekan "Hubungkan Telegram". Bila ini HP '
            'kasir: tekan "Kirim tautan ke HP Pemilik" (mis. lewat WhatsApp), '
            'lalu buka tautannya di HP Pemilik.',
          ),
          const _Step(3, 'Telegram terbuka → tekan MULAI / START.'),
          const _Step(
            4,
            'Biarkan layar ini terbuka sampai muncul "Terhubung".',
          ),
          const SizedBox(height: 20),
          if (_waiting) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            const Text(
              'Menunggu tombol START ditekan di Telegram…',
              textAlign: TextAlign.center,
            ),
            TextButton(
              onPressed: () => setState(() => _cancelled = true),
              child: const Text('Batal'),
            ),
          ] else ...[
            FilledButton.icon(
              key: const Key('telegram-connect'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
              ),
              onPressed: () => _connect(share: false),
              icon: const Icon(Icons.link),
              label: const Text('Hubungkan Telegram'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: () => _connect(share: true),
              icon: const Icon(Icons.share_outlined),
              label: const Text('Kirim tautan ke HP Pemilik'),
            ),
          ],
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step(this.number, this.text);

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(radius: 12, child: Text('$number')),
        const SizedBox(width: 12),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

class _Linked extends ConsumerWidget {
  const _Linked({required this.status});

  final TelegramStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final service = ref.read(telegramServiceProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          margin: const EdgeInsets.all(16),
          color: theme.colorScheme.primaryContainer,
          child: ListTile(
            leading: const Icon(Icons.check_circle_rounded),
            title: Text('Terhubung ke ${status.chatName}'),
            subtitle: Text(
              status.pending == 0
                  ? 'Semua pesan sudah terkirim'
                  : '${status.pending} pesan menunggu dikirim'
                        '${status.lastError == null ? '' : ' · ${status.lastError}'}',
              key: const Key('telegram-pending'),
            ),
          ),
        ),
        if (status.pending > 0)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              onPressed: () => service.flush(force: true),
              icon: const Icon(Icons.refresh),
              label: const Text('Coba kirim sekarang'),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text('Kirim ke Telegram', style: theme.textTheme.titleMedium),
        ),
        for (final t in TelegramTopic.values)
          SwitchListTile(
            title: Text(t.label),
            subtitle: Text(t.description),
            value: status.topics[t] ?? true,
            onChanged: (v) => service.setTopic(t, v),
          ),
        const Divider(height: 32),
        ListTile(
          leading: const Icon(Icons.notifications_active_outlined),
          title: const Text('Kirim pesan uji'),
          onTap: () async {
            await service.sendTest();
            if (context.mounted) showMessage(context, 'Pesan uji diantrekan');
          },
        ),
        ListTile(
          leading: const Icon(Icons.bar_chart_rounded),
          title: const Text('Kirim ringkasan hari ini'),
          subtitle: const Text('Penjualan sejauh ini'),
          onTap: () async {
            await service.queueTodaySummary();
            if (context.mounted) showMessage(context, 'Ringkasan diantrekan');
          },
        ),
        ListTile(
          leading: Icon(Icons.link_off, color: theme.colorScheme.error),
          title: const Text('Putuskan'),
          subtitle: const Text('Berhenti mengirim ke akun ini'),
          onTap: () async {
            final ok = await confirm(
              context,
              title: 'Putuskan Telegram?',
              message:
                  'Notifikasi berhenti dikirim dan pesan yang belum terkirim '
                  'dihapus. Bisa dihubungkan lagi kapan saja.',
              confirmLabel: 'Putuskan',
            );
            if (ok) await service.unlink();
          },
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
