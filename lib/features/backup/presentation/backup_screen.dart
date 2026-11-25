import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app.dart' show AppRestart;
import '../../../core/clock.dart';
import '../../../core/format.dart';
import '../../../core/widgets/common.dart';
import '../data/backup_service.dart';

/// Backup & pulihkan (khusus Pemilik).
class BackupScreen extends ConsumerWidget {
  const BackupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(backupStateProvider);
    final local = ref.watch(localBackupsProvider);
    final now = ref.watch(clockProvider)();

    return Scaffold(
      appBar: AppBar(title: const Text('Backup & Pulihkan')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ContentWidth(
            maxWidth: 600,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _StatusCard(state: state.value, now: now),
                const SizedBox(height: 12),
                Text(
                  'Backup berisi semua data: produk, stok, transaksi, pengguna, '
                  'pengaturan, dan foto produk. Simpan di luar HP ini (Google '
                  'Drive, WhatsApp ke nomor sendiri, atau flashdisk) agar data '
                  'tetap aman bila HP hilang atau rusak.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  key: const Key('backup-share'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                  ),
                  onPressed: () => _export(context, ref, share: true),
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('Kirim backup (Drive / WhatsApp)'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                  ),
                  onPressed: () => _export(context, ref, share: false),
                  icon: const Icon(Icons.save_alt_outlined),
                  label: const Text('Simpan ke penyimpanan HP / flashdisk'),
                ),
                const SizedBox(height: 32),
                Text('Pulihkan data', style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  'Mengganti semua data di HP ini dengan isi file backup. '
                  'Data saat ini disimpan dulu sebagai cadangan.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                  ),
                  onPressed: () =>
                      pickAndRestore(context, ref, fromSetup: false),
                  icon: const Icon(Icons.restore_rounded),
                  label: const Text('Pilih file backup…'),
                ),
                const SizedBox(height: 24),
                Text(
                  'Cadangan otomatis di HP ini',
                  style: theme.textTheme.titleMedium,
                ),
                Text(
                  'Dibuat setiap hari (tanpa foto), 7 hari terakhir. Berguna bila '
                  'ada data yang salah ubah/terhapus. Tidak melindungi bila HP hilang.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                ...switch (local) {
                  AsyncData(:final value) when value.isEmpty => [
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('Belum ada cadangan otomatis.'),
                    ),
                  ],
                  AsyncData(:final value) => [
                    for (final b in value)
                      Card(
                        child: ListTile(
                          leading: Icon(
                            b.kind == LocalBackupKind.daily
                                ? Icons.history_rounded
                                : Icons.restore_page_outlined,
                          ),
                          title: Text(formatDateTime(b.createdAt)),
                          subtitle: Text(b.kind.label),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => restoreFromFile(
                            context,
                            ref,
                            b.file,
                            fromSetup: false,
                            deleteSourceAfter: false,
                          ),
                        ),
                      ),
                  ],
                  AsyncError(:final error) => [Text('$error')],
                  _ => [const LinearProgressIndicator()],
                },
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _export(
    BuildContext context,
    WidgetRef ref, {
    required bool share,
  }) async {
    final service = await ref.read(backupServiceProvider.future);
    if (!context.mounted) return;
    final file = await runWithProgress(
      context,
      'Membuat backup…',
      service.createExport,
    );
    if (file == null || !context.mounted) return;

    var done = false;
    try {
      if (share) {
        final result = await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path, mimeType: 'application/zip')],
            subject: 'Backup POS Apotek',
            text:
                'Backup POS Apotek ${formatDateTime(ref.read(clockProvider)())}',
          ),
        );
        done = result.status != ShareResultStatus.dismissed;
      } else {
        final uri = await FilePicker.saveFile(
          fileName: file.uri.pathSegments.last,
          bytes: await file.readAsBytes(),
          mimeType: 'application/zip',
          dialogTitle: 'Simpan backup',
        );
        done = uri != null;
      }
    } on Object catch (e) {
      if (context.mounted) showMessage(context, 'Gagal: $e', error: true);
      return;
    }
    if (!done) return;
    await service.markExported();
    ref.invalidate(backupStateProvider);
    if (context.mounted) {
      final size = (await file.length()) / (1024 * 1024);
      if (!context.mounted) return;
      showMessage(context, 'Backup tersimpan (${size.toStringAsFixed(1)} MB)');
    }
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.state, required this.now});

  final BackupState? state;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final last = state?.lastExportAt;
    final due = isExportDue(state, now);
    final color = due
        ? theme.colorScheme.errorContainer
        : theme.colorScheme.primaryContainer;
    return Card(
      color: color,
      child: ListTile(
        leading: Icon(
          due ? Icons.warning_amber_rounded : Icons.cloud_done_outlined,
        ),
        title: Text(
          last == null
              ? 'Belum pernah backup ke luar HP'
              : 'Backup terakhir ke luar HP',
        ),
        subtitle: last == null
            ? const Text('Buat backup pertama sekarang.')
            : Text('${formatDateTime(last)} (${daysAgo(last, now)})'),
      ),
    );
  }
}

/// Apakah sudah waktunya mengingatkan backup ke luar HP.
bool isExportDue(BackupState? state, DateTime now) {
  final last = state?.lastExportAt;
  return last == null ||
      now.difference(last) >= BackupService.exportReminderAfter;
}

String daysAgo(DateTime t, DateTime now) {
  final days = DateTime(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime(t.year, t.month, t.day)).inDays;
  return switch (days) {
    <= 0 => 'hari ini',
    1 => 'kemarin',
    _ => '$days hari lalu',
  };
}

/// Menjalankan [task] sambil menampilkan dialog "harap tunggu".
/// Mengembalikan `null` (dan menampilkan pesan) bila gagal.
Future<T?> runWithProgress<T>(
  BuildContext context,
  String label,
  Future<T> Function() task,
) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Expanded(child: Text(label)),
          ],
        ),
      ),
    ),
  );
  var open = true;
  void close() {
    if (open) {
      open = false;
      navigator.pop();
    }
  }

  try {
    final result = await task();
    close();
    return result;
  } on BackupException catch (e) {
    close();
    if (context.mounted) showMessage(context, e.message, error: true);
    return null;
  } on Object catch (e) {
    close();
    if (context.mounted) showMessage(context, 'Gagal: $e', error: true);
    return null;
  }
}

/// Memilih file backup dari HP / Drive lalu memulihkannya.
Future<void> pickAndRestore(
  BuildContext context,
  WidgetRef ref, {
  required bool fromSetup,
}) async {
  final List<PlatformFile> picked;
  try {
    picked = await FilePicker.pickFiles(dialogTitle: 'Pilih file backup');
  } on Object catch (e) {
    if (context.mounted) {
      showMessage(context, 'Gagal membuka file: $e', error: true);
    }
    return;
  }
  if (picked.isEmpty || !context.mounted) return;

  final paths = await ref.read(appPathsProvider.future);
  if (!context.mounted) return;
  // File dari Drive/penyimpanan bisa berupa content://, salin dulu.
  final copy = await runWithProgress(context, 'Membaca file…', () async {
    final target = File('${paths.temp.path}/pilihan_backup.zip');
    final sink = target.openWrite();
    await sink.addStream(picked.first.readAsByteStream());
    await sink.close();
    return target;
  });
  if (copy == null || !context.mounted) return;
  await restoreFromFile(
    context,
    ref,
    copy,
    fromSetup: fromSetup,
    deleteSourceAfter: true,
  );
}

/// Memeriksa [file], meminta konfirmasi, lalu memulihkan & memulai ulang aplikasi.
Future<void> restoreFromFile(
  BuildContext context,
  WidgetRef ref,
  File file, {
  required bool fromSetup,
  required bool deleteSourceAfter,
}) async {
  final restart = AppRestart.maybeOf(context);
  final service = await ref.read(backupServiceProvider.future);
  if (!context.mounted) return;

  final staged = await runWithProgress(
    context,
    'Memeriksa file backup…',
    () => service.stage(file),
  );
  if (deleteSourceAfter && await file.exists()) await file.delete();
  if (staged == null || !context.mounted) return;

  final info = staged.info;
  final ok = await confirm(
    context,
    title: 'Pulihkan backup ini?',
    message: [
      if (info.storeName.isNotEmpty) info.storeName,
      'Dibuat ${formatDateTime(info.createdAt)}',
      '${formatNumber(info.productCount)} produk · ${formatNumber(info.saleCount)} transaksi · '
          '${info.userCount} pengguna',
      info.includesPhotos
          ? '${info.photoCount} foto produk'
          : 'Tanpa foto (foto yang ada tetap dipakai)',
      '',
      if (fromSetup)
        'Setelah dipulihkan, masuk dengan nama & PIN yang ada di backup.'
      else
        'SEMUA data di HP ini akan diganti. Data saat ini disimpan dulu sebagai '
            'cadangan "Sebelum pemulihan". Setelah selesai, aplikasi dibuka ulang '
            'dan semua pengguna masuk lagi dengan PIN yang ada di backup.',
    ].join('\n'),
    confirmLabel: 'Pulihkan',
    destructive: !fromSetup,
  );
  if (!ok || !context.mounted || restart == null) {
    await staged.directory.delete(recursive: true);
    if (ok && restart == null && context.mounted) {
      showMessage(context, 'Pemulihan tidak tersedia di mode ini', error: true);
    }
    return;
  }

  if (!fromSetup) {
    final saved = await runWithProgress(
      context,
      'Menyimpan data saat ini…',
      service.createBeforeRestore,
    );
    if (saved == null) {
      await staged.directory.delete(recursive: true);
      return;
    }
  }
  await restart.restart(() => applyRestore(staged, service.paths));
}
