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
                    ? const [_NotConfigured()]
                    : value.linked
                    ? [_Linked(status: value)]
                    : const [_NotLinked()],
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

class _NotConfigured extends StatelessWidget {
  const _NotConfigured();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(24),
    child: Text(
      'Notifikasi Telegram belum disiapkan di aplikasi ini. Minta pembuat '
      'aplikasi membuat bot Telegram dan memasang ulang aplikasi.',
      textAlign: TextAlign.center,
    ),
  );
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
    final link = service.linkUri(code);
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
