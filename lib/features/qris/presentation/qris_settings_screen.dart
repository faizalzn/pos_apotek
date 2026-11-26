import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/widgets/common.dart';
import '../../products/presentation/barcode_scanner_screen.dart';
import '../data/qris.dart';
import '../data/qris_repository.dart';
import 'qris_widgets.dart';

/// Mengatur QRIS apotek agar QR di kasir otomatis berisi nominal (Pemilik).
class QrisSettingsScreen extends ConsumerStatefulWidget {
  const QrisSettingsScreen({super.key});

  @override
  ConsumerState<QrisSettingsScreen> createState() => _QrisSettingsScreenState();
}

class _QrisSettingsScreenState extends ConsumerState<QrisSettingsScreen> {
  bool _busy = false;

  Future<void> _save(String? raw) async {
    if (raw == null || !mounted) return;
    try {
      final q = await ref.read(qrisRepositoryProvider).save(raw);
      if (mounted) showMessage(context, 'QRIS ${q.merchantName} tersimpan');
    } on QrisException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    }
  }

  Future<void> _scan() async => _save(await scanBarcode(context));

  Future<void> _fromImage() async {
    setState(() => _busy = true);
    final scanner = MobileScannerController(autoStart: false);
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picked == null) return;
      final capture = await scanner.analyzeImage(
        picked.path,
        formats: const [BarcodeFormat.qrCode],
      );
      final raw = capture?.barcodes
          .map((b) => b.rawValue)
          .whereType<String>()
          .firstOrNull;
      if (raw == null) {
        if (mounted) {
          showMessage(
            context,
            'Tidak ada kode QR di gambar itu. Coba gambar yang lebih jelas.',
            error: true,
          );
        }
        return;
      }
      await _save(raw);
    } on Object catch (e) {
      if (mounted) {
        showMessage(context, 'Gambar tidak bisa dibaca: $e', error: true);
      }
    } finally {
      await scanner.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    await _save(data?.text);
  }

  @override
  Widget build(BuildContext context) {
    final qris = ref.watch(qrisProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('QRIS Apotek')),
      body: switch (qris) {
        AsyncData(:final value) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ContentWidth(
              maxWidth: 560,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (value == null) ...[
                    Icon(
                      Icons.qr_code_2,
                      size: 64,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'QRIS dengan nominal otomatis',
                      style: theme.textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Scan sekali stiker QRIS apotek. Setelah itu, setiap '
                      'pembayaran QRIS di kasir menampilkan QR yang nominalnya '
                      'sudah terisi, jadi pelanggan tidak salah ketik. Uang tetap '
                      'masuk ke rekening QRIS apotek seperti biasa, tanpa biaya '
                      'tambahan dari aplikasi ini.',
                      textAlign: TextAlign.center,
                    ),
                  ] else
                    _Saved(qris: value),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    key: const Key('qris-scan'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                    ),
                    onPressed: _busy ? null : _scan,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: Text(
                      value == null
                          ? 'Scan stiker QRIS'
                          : 'Ganti: scan stiker QRIS',
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    onPressed: _busy ? null : _fromImage,
                    icon: const Icon(Icons.image_outlined),
                    label: const Text('Ambil dari gambar / screenshot QRIS'),
                  ),
                  TextButton(
                    onPressed: _busy ? null : _paste,
                    child: const Text('Tempel teks QRIS'),
                  ),
                  if (value != null)
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                      ),
                      onPressed: () async {
                        final ok = await confirm(
                          context,
                          title: 'Hapus QRIS?',
                          message:
                              'Kasir kembali memakai stiker QRIS dan pelanggan '
                              'mengetik nominal sendiri.',
                          confirmLabel: 'Hapus',
                        );
                        if (ok) await ref.read(qrisRepositoryProvider).clear();
                      },
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Hapus QRIS'),
                    ),
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

class _Saved extends StatelessWidget {
  const _Saved({required this.qris});

  final Qris qris;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          color: theme.colorScheme.primaryContainer,
          child: ListTile(
            leading: const Icon(Icons.check_circle_rounded),
            title: Text(qris.merchantName, key: const Key('qris-merchant')),
            subtitle: Text(
              [
                if (qris.city.isNotEmpty) qris.city,
                if (qris.nmid case final n?) 'NMID $n',
              ].join(' · '),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Uji coba (wajib sekali)', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        const Text(
          'Scan QR di bawah dengan aplikasi bank / e-wallet di HP lain. Pastikan '
          'nama merchant sama dan nominal Rp1 terisi otomatis. Tidak perlu '
          'dibayar. Bila aplikasi menolak, hapus QRIS ini dan pakai stiker '
          'seperti biasa.',
        ),
        const SizedBox(height: 12),
        Center(child: QrisCode(data: qris.withAmount(1), size: 200)),
      ],
    );
  }
}
