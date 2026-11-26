import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/database/app_database.dart';
import '../../../core/format.dart';
import '../../../core/widgets/common.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/data/user_repository.dart' show UserRuleException;
import '../../receipt/data/printer_settings.dart';
import '../../receipt/data/receipt_service.dart';
import '../../settings/data/settings_repository.dart';
import '../data/shift_excel.dart';
import '../data/shift_receipt.dart';
import '../data/shift_service.dart';

/// Menu Shift: status shift berjalan, kas masuk/keluar, tutup shift, riwayat.
class ShiftScreen extends ConsumerWidget {
  const ShiftScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = ref.watch(openShiftProvider);
    final isOwner = ref.watch(isOwnerProvider);
    final me = ref.watch(sessionProvider);
    final recent = ref.watch(recentShiftsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Shift')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ContentWidth(
            maxWidth: 640,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                switch (open) {
                  AsyncData(value: final shift?) => _OpenShiftPanel(
                    shiftId: shift.id,
                  ),
                  AsyncData() => _NoShiftPanel(),
                  AsyncError(:final error) => Text('$error'),
                  _ => const LinearProgressIndicator(),
                },
                const SizedBox(height: 24),
                Text('Riwayat shift', style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                ...switch (recent) {
                  AsyncData(:final value) => [
                    for (final s in value.where(
                      (s) =>
                          !s.isOpen && (isOwner || s.shift.openedBy == me?.id),
                    ))
                      ShiftTile(summary: s),
                    if (value.every((s) => s.isOpen))
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('Belum ada shift yang ditutup.'),
                      ),
                  ],
                  _ => [const SizedBox.shrink()],
                },
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NoShiftPanel extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              Icons.lock_clock_outlined,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 8),
            Text(
              'Belum ada shift yang dibuka',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            const Text(
              'Buka shift sebelum mulai berjualan. Hitung dulu uang di laci.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('open-shift'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
              ),
              onPressed: () => openShiftFlow(context, ref),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Buka shift'),
            ),
          ],
        ),
      ),
    );
  }
}

class _OpenShiftPanel extends ConsumerWidget {
  const _OpenShiftPanel({required this.shiftId});

  final String shiftId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(shiftSummaryProvider(shiftId));
    return switch (summary) {
      AsyncData(:final value) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ShiftSummaryCard(summary: value),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  onPressed: () =>
                      _cashEntry(context, ref, CashEntryType.cashIn),
                  icon: const Icon(Icons.add),
                  label: const Text('Kas masuk'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('cash-out'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  onPressed: () =>
                      _cashEntry(context, ref, CashEntryType.cashOut),
                  icon: const Icon(Icons.remove),
                  label: const Text('Kas keluar'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const Key('close-shift'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
            ),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => CloseShiftScreen(shiftId: shiftId),
              ),
            ),
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('Tutup shift'),
          ),
        ],
      ),
      AsyncError(:final error) => Text('$error'),
      _ => const LinearProgressIndicator(),
    };
  }

  Future<void> _cashEntry(
    BuildContext context,
    WidgetRef ref,
    CashEntryType type,
  ) async {
    final amount = TextEditingController();
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(type.label),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              type == CashEntryType.cashOut
                  ? 'Uang yang diambil dari laci, mis. beli galon, bayar listrik, '
                        'disetor ke Pemilik.'
                  : 'Uang yang ditambahkan ke laci, mis. uang kecil untuk kembalian.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amount,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [ThousandsInputFormatter()],
              decoration: const InputDecoration(
                labelText: 'Jumlah',
                prefixText: 'Rp ',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: note,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Keterangan *'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref
          .read(shiftServiceProvider)
          .addCashEntry(
            type: type,
            amount: parseNumber(amount.text),
            note: note.text,
            by: ref.read(sessionProvider)!,
          );
      if (context.mounted) showMessage(context, '${type.label} tercatat');
    } on UserRuleException catch (e) {
      if (context.mounted) showMessage(context, e.message, error: true);
    }
  }
}

/// Dialog buka shift (modal awal). Mengembalikan `true` bila shift dibuka.
Future<bool> openShiftFlow(BuildContext context, WidgetRef ref) async {
  final service = ref.read(shiftServiceProvider);
  final last = await service.lastCountedCash();
  if (!context.mounted) return false;
  final controller = TextEditingController(
    text: last == null ? '' : formatNumber(last),
  );
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Buka shift'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Hitung uang yang ada di laci sekarang (modal untuk kembalian).',
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('opening-cash'),
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [ThousandsInputFormatter()],
            decoration: InputDecoration(
              labelText: 'Uang di laci',
              prefixText: 'Rp ',
              helperText: last == null
                  ? 'Isi 0 bila laci kosong'
                  : 'Saat shift terakhir ditutup: ${formatRupiah(last)}',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Batal'),
        ),
        FilledButton(
          key: const Key('confirm-open-shift'),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Buka shift'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;
  try {
    await service.open(
      by: ref.read(sessionProvider)!,
      openingCash: parseNumber(controller.text),
    );
    if (context.mounted) showMessage(context, 'Shift dibuka');
    return true;
  } on UserRuleException catch (e) {
    if (context.mounted) showMessage(context, e.message, error: true);
    return false;
  }
}

/// Ringkasan uang shift.
class ShiftSummaryCard extends StatelessWidget {
  const ShiftSummaryCard({super.key, required this.summary});

  final ShiftSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = summary;
    Widget row(String label, String value, {bool bold = false, Color? color}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: bold ? theme.textTheme.titleMedium : null,
                ),
              ),
              Text(
                value,
                style:
                    (bold
                            ? theme.textTheme.titleMedium
                            : theme.textTheme.bodyLarge)
                        ?.copyWith(color: color),
              ),
            ],
          ),
        );
    final diff = s.difference;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  s.isOpen
                      ? Icons.lock_open_rounded
                      : Icons.lock_outline_rounded,
                  color: s.isOpen
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    s.isOpen
                        ? 'Shift berjalan · ${s.openedByName}'
                        : 'Shift ${s.openedByName}',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            Text(
              s.isOpen
                  ? 'Dibuka ${formatDateTime(s.shift.openedAt)}'
                  : '${formatDateTime(s.shift.openedAt)} – ${formatDateTime(s.shift.closedAt!)}'
                        '${s.closedByName != null && s.closedByName != s.openedByName ? ' · ditutup ${s.closedByName}' : ''}',
              style: theme.textTheme.bodySmall,
            ),
            const Divider(height: 24),
            row('Penjualan', '${s.saleCount} transaksi'),
            row('  Tunai', formatRupiah(s.cashSales)),
            row('  QRIS', formatRupiah(s.qrisSales)),
            if (s.voidCount > 0)
              row('  Dibatalkan', '${s.voidCount} transaksi'),
            const Divider(height: 24),
            row('Modal awal', formatRupiah(s.shift.openingCash)),
            row('+ Penjualan tunai', formatRupiah(s.cashSales)),
            if (s.cashIn > 0) row('+ Kas masuk', formatRupiah(s.cashIn)),
            if (s.cashOut > 0) row('− Kas keluar', formatRupiah(s.cashOut)),
            if (s.refunds > 0)
              row('− Pengembalian (batal)', formatRupiah(s.refunds)),
            row(
              s.isOpen ? 'Seharusnya di laci' : 'Seharusnya',
              formatRupiah(s.expectedCash),
              bold: true,
            ),
            if (!s.isOpen) ...[
              row(
                'Dihitung',
                formatRupiah(s.shift.countedCash ?? 0),
                bold: true,
              ),
              row(
                'Selisih',
                diffLabel(diff ?? 0),
                bold: true,
                color: (diff ?? 0) == 0
                    ? theme.colorScheme.primary
                    : theme.colorScheme.error,
              ),
              if (s.shift.closingNote.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Catatan: ${s.shift.closingNote}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
            ],
            if (s.entries.isNotEmpty) ...[
              const Divider(height: 24),
              Text('Kas masuk/keluar', style: theme.textTheme.titleSmall),
              for (final e in s.entries)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(e.entry.note),
                  subtitle: Text(
                    '${formatDateTime(e.entry.createdAt)} · ${e.userName}',
                  ),
                  trailing: Text(
                    '${e.signedAmount > 0 ? '+' : '−'}${formatRupiah(e.entry.amount)}',
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

String diffLabel(int diff) => switch (diff) {
  0 => 'Pas',
  > 0 => 'Lebih ${formatRupiah(diff)}',
  _ => 'Kurang ${formatRupiah(-diff)}',
};

class ShiftTile extends StatelessWidget {
  const ShiftTile({super.key, required this.summary});

  final ShiftSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = summary;
    final diff = s.difference ?? 0;
    return Card(
      child: ListTile(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ShiftDetailScreen(shiftId: s.shift.id),
          ),
        ),
        title: Text('${formatDateTime(s.shift.openedAt)} · ${s.openedByName}'),
        subtitle: Text(
          '${s.saleCount} transaksi · ${formatRupiah(s.totalSales)}',
        ),
        trailing: s.isOpen
            ? const Text('Berjalan')
            : Text(
                diffLabel(diff),
                style: TextStyle(
                  color: diff == 0
                      ? theme.colorScheme.primary
                      : theme.colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }
}

class ShiftDetailScreen extends ConsumerWidget {
  const ShiftDetailScreen({super.key, required this.shiftId});

  final String shiftId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(shiftSummaryProvider(shiftId));
    return Scaffold(
      appBar: AppBar(title: const Text('Detail Shift')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ContentWidth(
            maxWidth: 640,
            child: switch (summary) {
              AsyncData(:final value) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ShiftSummaryCard(summary: value),
                  if (!value.isOpen) ...[
                    const SizedBox(height: 12),
                    PrintShiftButton(summary: value),
                    const SizedBox(height: 8),
                    ShareShiftExcelButton(summary: value),
                  ],
                ],
              ),
              AsyncError(:final error) => Text('$error'),
              _ => const LinearProgressIndicator(),
            },
          ),
        ],
      ),
    );
  }
}

/// Cetak ringkasan shift ke printer thermal (bila sudah diatur).
class PrintShiftButton extends ConsumerWidget {
  const PrintShiftButton({super.key, required this.summary});

  final ShiftSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(printerSettingsProvider).value;
    if (settings == null || !settings.isThermal || !settings.isReady) {
      return const SizedBox.shrink();
    }
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      onPressed: () async {
        try {
          final store = ref.read(storeProfileProvider).value;
          await ref
              .read(receiptServiceProvider)
              .printLines(
                buildShiftReceipt(
                  summary,
                  storeName: store?.name ?? '',
                  columns: settings.paper.columns,
                ),
              );
          if (context.mounted) showMessage(context, 'Ringkasan shift dicetak');
        } on Object catch (e) {
          if (context.mounted) showMessage(context, '$e', error: true);
        }
      },
      icon: const Icon(Icons.print_outlined),
      label: const Text('Cetak ringkasan shift'),
    );
  }
}

/// Tutup shift: hitung uang di laci, bandingkan dengan seharusnya.
class CloseShiftScreen extends ConsumerStatefulWidget {
  const CloseShiftScreen({super.key, required this.shiftId});

  final String shiftId;

  @override
  ConsumerState<CloseShiftScreen> createState() => _CloseShiftScreenState();
}

class _CloseShiftScreenState extends ConsumerState<CloseShiftScreen> {
  final _counted = TextEditingController();
  final _note = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _counted.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    setState(() => _saving = true);
    try {
      final result = await ref
          .read(shiftServiceProvider)
          .close(
            shiftId: widget.shiftId,
            countedCash: parseNumber(_counted.text),
            note: _note.text,
            by: ref.read(sessionProvider)!,
          );
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ShiftClosedScreen(summary: result),
        ),
      );
    } on UserRuleException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(shiftSummaryProvider(widget.shiftId));
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Tutup Shift')),
      body: switch (summary) {
        AsyncData(:final value) => () {
          final expected = value.expectedCash;
          final filled = _counted.text.isNotEmpty;
          final diff = parseNumber(_counted.text) - expected;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ContentWidth(
                maxWidth: 560,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ShiftSummaryCard(summary: value),
                    const SizedBox(height: 16),
                    Text(
                      'Hitung uang di laci',
                      style: theme.textTheme.titleLarge,
                    ),
                    const Text(
                      'Hitung semua uang tunai di laci, lalu isi jumlahnya.',
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('counted-cash'),
                      controller: _counted,
                      keyboardType: TextInputType.number,
                      inputFormatters: [ThousandsInputFormatter()],
                      style: theme.textTheme.headlineSmall,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Uang di laci',
                        prefixText: 'Rp ',
                      ),
                    ),
                    if (filled) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: diff == 0
                              ? theme.colorScheme.primaryContainer
                              : theme.colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          diff == 0 ? 'Uang pas ✓' : diffLabel(diff),
                          key: const Key('shift-diff'),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall,
                        ),
                      ),
                      if (diff != 0) ...[
                        const SizedBox(height: 12),
                        TextField(
                          key: const Key('shift-note'),
                          controller: _note,
                          textCapitalization: TextCapitalization.sentences,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'Keterangan selisih *',
                            hintText:
                                'mis. salah kembalian, lupa catat kas keluar',
                            helperText: 'Wajib diisi bila uang tidak pas',
                          ),
                        ),
                      ],
                    ],
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      key: const Key('confirm-close-shift'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                      ),
                      onPressed:
                          !filled ||
                              _saving ||
                              (diff != 0 && _note.text.trim().isEmpty)
                          ? null
                          : _close,
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Tutup shift'),
                    ),
                  ],
                ),
              ),
            ],
          );
        }(),
        AsyncError(:final error) => Center(child: Text('$error')),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class ShiftClosedScreen extends StatelessWidget {
  const ShiftClosedScreen({super.key, required this.summary});

  final ShiftSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Shift Ditutup')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ContentWidth(
            maxWidth: 560,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  size: 72,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 8),
                Text(
                  'Shift berhasil ditutup',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                ShiftSummaryCard(summary: summary),
                const SizedBox(height: 12),
                PrintShiftButton(summary: summary),
                const SizedBox(height: 8),
                ShareShiftExcelButton(summary: summary),
                const SizedBox(height: 8),
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Selesai'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Bagikan laporan Excel shift (khusus Pemilik: berisi HPP & laba).
class ShareShiftExcelButton extends ConsumerStatefulWidget {
  const ShareShiftExcelButton({super.key, required this.summary});

  final ShiftSummary summary;

  @override
  ConsumerState<ShareShiftExcelButton> createState() =>
      _ShareShiftExcelButtonState();
}

class _ShareShiftExcelButtonState extends ConsumerState<ShareShiftExcelButton> {
  bool _busy = false;

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      final file = await ref
          .read(shiftExcelProvider)
          .writeFile(widget.summary.shift.id);
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile(
              file.path,
              mimeType:
                  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            ),
          ],
          subject: 'Laporan shift ${widget.summary.openedByName}',
        ),
      );
    } on Object catch (e) {
      if (mounted) showMessage(context, 'Excel gagal dibuat: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(isOwnerProvider)) return const SizedBox.shrink();
    return OutlinedButton.icon(
      key: const Key('share-shift-excel'),
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      onPressed: _busy ? null : _share,
      icon: _busy
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.table_view_outlined),
      label: const Text('Bagikan laporan Excel'),
    );
  }
}
