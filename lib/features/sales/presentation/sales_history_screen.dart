import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/clock.dart';
import '../../../core/database/app_database.dart';
import '../../../core/format.dart';
import '../../../core/widgets/common.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/data/user_repository.dart' show UserRuleException;
import '../../products/presentation/widgets/product_widgets.dart';
import '../../receipt/presentation/receipt_actions.dart';
import '../data/sale_service.dart';

/// Daftar transaksi per hari.
class SalesHistoryScreen extends ConsumerStatefulWidget {
  const SalesHistoryScreen({super.key});

  @override
  ConsumerState<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends ConsumerState<SalesHistoryScreen> {
  late DateTime _day = _dateOnly(ref.read(clockProvider)());

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = _dateOnly(ref.watch(clockProvider)());
    final sales = ref.watch(salesOfDayProvider(_day));

    return Scaffold(
      appBar: AppBar(title: const Text('Riwayat Transaksi')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Hari sebelumnya',
                  onPressed: () => setState(
                    () => _day = _day.subtract(const Duration(days: 1)),
                  ),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: TextButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _day,
                        firstDate: DateTime(2024),
                        lastDate: today,
                      );
                      if (picked != null) setState(() => _day = picked);
                    },
                    child: Text(
                      _day == today
                          ? 'Hari ini'
                          : '${_day.day} ${monthNames[_day.month - 1]} ${_day.year}',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Hari berikutnya',
                  onPressed: _day.isBefore(today)
                      ? () => setState(
                          () => _day = _day.add(const Duration(days: 1)),
                        )
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
          Expanded(
            child: sales.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
              data: (list) {
                final done = list.where(
                  (e) => e.sale.status == SaleStatus.completed,
                );
                final total = done.fold(0, (s, e) => s + e.sale.total);
                return Column(
                  children: [
                    Card(
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${done.length} transaksi',
                                    style: theme.textTheme.titleMedium,
                                  ),
                                  if (list.length != done.length)
                                    Text(
                                      '${list.length - done.length} dibatalkan',
                                      style: theme.textTheme.bodySmall,
                                    ),
                                ],
                              ),
                            ),
                            Text(
                              formatRupiah(total),
                              key: const Key('day-total'),
                              style: theme.textTheme.headlineSmall?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: list.isEmpty
                          ? const Center(child: Text('Belum ada transaksi'))
                          : ListView.separated(
                              itemCount: list.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, i) =>
                                  _SaleTile(entry: list[i]),
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SaleTile extends StatelessWidget {
  const _SaleTile({required this.entry});

  final SaleEntry entry;

  @override
  Widget build(BuildContext context) {
    final s = entry.sale;
    final voided = s.status == SaleStatus.voided;
    final theme = Theme.of(context);
    String two(int n) => n.toString().padLeft(2, '0');
    return ListTile(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => SaleDetailScreen(saleId: s.id)),
      ),
      leading: CircleAvatar(
        child: Icon(
          s.paymentMethod == PaymentMethod.cash
              ? Icons.payments_outlined
              : Icons.qr_code_2,
        ),
      ),
      title: Text(
        '${two(s.createdAt.hour)}.${two(s.createdAt.minute)} · ${s.number}',
      ),
      subtitle: Text('${entry.cashierName} · ${s.paymentMethod.label}'),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            formatRupiah(s.total),
            style: theme.textTheme.titleMedium?.copyWith(
              decoration: voided ? TextDecoration.lineThrough : null,
              color: voided ? theme.colorScheme.outline : null,
            ),
          ),
          if (voided)
            const StatusChip(label: 'Dibatalkan', color: expiredColor),
        ],
      ),
    );
  }
}

class SaleDetailScreen extends ConsumerWidget {
  const SaleDetailScreen({super.key, required this.saleId});

  final String saleId;

  Future<void> _void(BuildContext context, WidgetRef ref, Sale sale) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Batalkan ${sale.number}?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Stok barang akan dikembalikan. Transaksi tetap tercatat '
              'sebagai "dibatalkan" dan tidak dihitung di laporan.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reason,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Alasan *',
                hintText: 'mis. salah input jumlah',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Tidak'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Batalkan transaksi'),
          ),
        ],
      ),
    );
    final text = reason.text;
    if (ok != true || !context.mounted) return;
    try {
      await ref
          .read(saleServiceProvider)
          .voidSale(
            saleId: sale.id,
            reason: text,
            by: ref.read(sessionProvider)!,
          );
      if (context.mounted) {
        showMessage(context, 'Transaksi dibatalkan, stok dikembalikan');
      }
    } on UserRuleException catch (e) {
      if (context.mounted) showMessage(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(saleDetailProvider(saleId));
    final isOwner = ref.watch(isOwnerProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Detail Transaksi')),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (d) {
          if (d == null) {
            return const Center(child: Text('Transaksi tidak ditemukan'));
          }
          final s = d.sale;
          final voided = s.status == SaleStatus.voided;
          Widget row(
            String label,
            String value, {
            bool bold = false,
          }) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Text(label, style: bold ? theme.textTheme.titleMedium : null),
                const Spacer(),
                Text(value, style: bold ? theme.textTheme.titleMedium : null),
              ],
            ),
          );
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ContentWidth(
                maxWidth: 560,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(s.number, style: theme.textTheme.headlineSmall),
                    Text(
                      '${formatDateTime(s.createdAt)} · Kasir ${d.cashierName}',
                    ),
                    if (voided) ...[
                      const SizedBox(height: 12),
                      Card(
                        color: theme.colorScheme.errorContainer,
                        child: ListTile(
                          title: const Text('Dibatalkan'),
                          subtitle: Text(
                            '${d.voidedByName ?? ''} · ${formatDateTime(s.voidedAt!)}\n${s.voidReason}',
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            for (final item in d.items) ...[
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.productName,
                                          style: theme.textTheme.titleSmall,
                                        ),
                                        Text(
                                          '${item.quantity} ${item.unitName} × ${formatRupiah(item.unitPrice)}'
                                          '${item.discount > 0 ? ' − ${formatRupiah(item.discount)}' : ''}',
                                          style: theme.textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(formatRupiah(item.lineTotal)),
                                ],
                              ),
                              const SizedBox(height: 10),
                            ],
                            const Divider(),
                            row('Subtotal', formatRupiah(s.subtotal)),
                            if (s.itemDiscount > 0)
                              row(
                                'Diskon barang',
                                '−${formatRupiah(s.itemDiscount)}',
                              ),
                            if (s.discount > 0)
                              row(
                                'Diskon total',
                                '−${formatRupiah(s.discount)}',
                              ),
                            row('Total', formatRupiah(s.total), bold: true),
                            row(
                              s.paymentMethod == PaymentMethod.cash
                                  ? 'Tunai'
                                  : 'QRIS',
                              formatRupiah(s.amountPaid),
                            ),
                            if (s.change > 0)
                              row('Kembalian', formatRupiah(s.change)),
                            if (isOwner) ...[
                              const Divider(),
                              row(
                                'Harga beli',
                                formatRupiah(s.costTotal.round()),
                              ),
                              row(
                                'Laba kotor',
                                formatRupiah((s.total - s.costTotal).round()),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ReceiptActions(saleId: s.id, isCopy: true),
                    if (isOwner && !voided) ...[
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: theme.colorScheme.error,
                        ),
                        onPressed: () => _void(context, ref, s),
                        icon: const Icon(Icons.cancel_outlined),
                        label: const Text('Batalkan transaksi'),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
