import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/clock.dart';
import '../../../core/database/app_database.dart';
import '../../../core/format.dart';
import '../../../core/widgets/common.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/data/user_repository.dart' show UserRuleException;
import '../data/product_models.dart';
import '../data/product_repository.dart';
import 'product_form_screen.dart';
import 'stock_in_screen.dart';
import 'widgets/product_widgets.dart';

class ProductDetailScreen extends ConsumerWidget {
  const ProductDetailScreen({super.key, required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final product = ref.watch(productProvider(productId));
    final isOwner = ref.watch(isOwnerProvider);

    return product.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('$e'))),
      data: (p) {
        if (p == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('Produk tidak ditemukan')),
          );
        }
        return Scaffold(
          appBar: AppBar(
            title: const Text('Detail Produk'),
            actions: [
              if (isOwner)
                IconButton(
                  tooltip: 'Ubah',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ProductFormScreen(existing: p),
                    ),
                  ),
                ),
              PopupMenuButton<String>(
                onSelected: (v) => _menu(context, ref, p, v),
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'history',
                    child: Text('Riwayat stok'),
                  ),
                  if (isOwner)
                    PopupMenuItem(
                      value: 'archive',
                      child: Text(
                        p.product.isActive
                            ? 'Arsipkan produk'
                            : 'Aktifkan kembali',
                      ),
                    ),
                ],
              ),
            ],
          ),
          floatingActionButton: p.product.isActive
              ? FloatingActionButton.extended(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => StockInScreen(productId: productId),
                    ),
                  ),
                  icon: const Icon(Icons.add_box_outlined),
                  label: const Text('Tambah stok'),
                )
              : null,
          body: _Body(summary: p, isOwner: isOwner),
        );
      },
    );
  }

  Future<void> _menu(
    BuildContext context,
    WidgetRef ref,
    ProductSummary p,
    String value,
  ) async {
    switch (value) {
      case 'history':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => _MovementsScreen(summary: p)),
        );
      case 'archive':
        final archive = p.product.isActive;
        if (archive) {
          final ok = await confirm(
            context,
            title: 'Arsipkan ${p.product.name}?',
            message:
                'Produk tidak akan tampil di kasir dan daftar produk. '
                'Riwayatnya tetap tersimpan dan bisa diaktifkan kembali.',
            confirmLabel: 'Arsipkan',
          );
          if (!ok) return;
        }
        await ref
            .read(productRepositoryProvider)
            .setArchived(p.product.id, archived: archive);
        if (context.mounted) {
          showMessage(
            context,
            archive ? 'Produk diarsipkan' : 'Produk aktif kembali',
          );
        }
    }
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.summary, required this.isOwner});

  final ProductSummary summary;
  final bool isOwner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final p = summary.product;
    final now = ref.watch(clockProvider)();
    final warnings = productWarnings(summary, now);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        ContentWidth(
          maxWidth: 720,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: p.photoFile == null
                        ? null
                        : () => showDialog<void>(
                            context: context,
                            builder: (_) => Dialog(
                              child: ProductPhoto(
                                photoFile: p.photoFile,
                                drugClass: p.drugClass,
                                size: 320,
                              ),
                            ),
                          ),
                    child: ProductPhoto(
                      photoFile: p.photoFile,
                      drugClass: p.drugClass,
                      size: 96,
                      radius: 16,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.name, style: theme.textTheme.headlineSmall),
                        if (p.genericName.isNotEmpty) Text(p.genericName),
                        const SizedBox(height: 6),
                        DrugClassBadge(p.drugClass),
                        if (p.category.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(p.category, style: theme.textTheme.bodySmall),
                        ],
                        if (!p.isActive) ...[
                          const SizedBox(height: 6),
                          const StatusChip(
                            label: 'Diarsipkan',
                            color: Colors.grey,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (p.drugClass.requiresPrescription) ...[
                const SizedBox(height: 12),
                Card(
                  color: theme.colorScheme.errorContainer,
                  child: ListTile(
                    leading: Icon(
                      Icons.assignment_outlined,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                    title: Text(
                      'Perlu resep dokter',
                      style: TextStyle(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              _Section(
                title: 'Stok',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formatStock(summary.stock, summary.units),
                      style: theme.textTheme.headlineSmall,
                    ),
                    if (summary.units.length > 1 && summary.stock > 0)
                      Text(
                        '${formatNumber(summary.stock)} ${summary.baseUnit.name}',
                      ),
                    if (warnings.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(spacing: 6, runSpacing: 4, children: warnings),
                    ],
                    if (summary.lowStockThreshold > 0) ...[
                      const SizedBox(height: 8),
                      Text(
                        summary.isAutoLowStock
                            ? 'Diingatkan bila kurang dari 1 ${summary.units[1].name} (otomatis)'
                            : 'Diingatkan bila stok ≤ ${formatNumber(p.minStock)} ${summary.baseUnit.name}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              _Section(
                title: 'Harga jual',
                child: Column(
                  children: [
                    for (final u in summary.units)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(u.name),
                        subtitle: Text(
                          [
                            if (u.multiplier > 1)
                              'isi ${u.multiplier} ${summary.baseUnit.name}',
                            if (u.barcode != null) 'Barcode ${u.barcode}',
                          ].join(' · '),
                        ),
                        trailing: Text(
                          formatRupiah(u.sellPrice),
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                    if (isOwner && summary.stock > 0)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Harga beli rata-rata'),
                        subtitle: Text('per ${summary.baseUnit.name}'),
                        trailing: Text(
                          formatRupiah(summary.averageCost.round()),
                        ),
                      ),
                  ],
                ),
              ),
              _Section(
                title: 'Batch & kedaluwarsa',
                child: summary.batches.isEmpty
                    ? const Text('Belum ada stok. Tekan "Tambah stok".')
                    : Column(
                        children: [
                          for (final b in summary.batches)
                            _BatchTile(
                              batch: b,
                              summary: summary,
                              now: now,
                              canEdit: isOwner,
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          child,
        ],
      ),
    ),
  );
}

class _BatchTile extends ConsumerWidget {
  const _BatchTile({
    required this.batch,
    required this.summary,
    required this.now,
    required this.canEdit,
  });

  final StockBatch batch;
  final ProductSummary summary;
  final DateTime now;
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = summary.batchStatus(batch, now);
    final color = switch (status) {
      ExpiryStatus.expired => expiredColor,
      ExpiryStatus.soon => soonColor,
      _ => null,
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: canEdit ? () => _actions(context, ref) : null,
      leading: Icon(
        status == ExpiryStatus.expired
            ? Icons.error_outline
            : status == ExpiryStatus.soon
            ? Icons.schedule
            : Icons.inventory_2_outlined,
        color: color,
      ),
      title: Text(
        'ED ${formatExpiry(batch.expiryDate)}',
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        [
          if (batch.batchNumber.isNotEmpty) 'Batch ${batch.batchNumber}',
          if (status == ExpiryStatus.expired) 'Kedaluwarsa — jangan dijual',
        ].join(' · '),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(formatStock(batch.quantity, summary.units)),
          if (canEdit) const Icon(Icons.more_vert),
        ],
      ),
    );
  }

  Future<void> _actions(BuildContext context, WidgetRef ref) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text('ED ${formatExpiry(batch.expiryDate)}'),
              subtitle: Text(formatStock(batch.quantity, summary.units)),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.fact_check_outlined),
              title: const Text('Koreksi jumlah (stock opname)'),
              subtitle: const Text('Jika jumlah fisik berbeda dengan aplikasi'),
              onTap: () => Navigator.pop(context, 'adjust'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_sweep_outlined),
              title: const Text('Buang (kedaluwarsa / rusak)'),
              onTap: () => Navigator.pop(context, 'dispose'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;

    final base = summary.baseUnit.name;
    final result = await _askQuantity(
      context,
      title: action == 'adjust' ? 'Jumlah sebenarnya' : 'Jumlah yang dibuang',
      unitName: base,
      initial: batch.quantity,
      noteHint: action == 'adjust'
          ? 'mis. hasil hitung ulang'
          : 'mis. kedaluwarsa / kemasan rusak',
    );
    if (result == null || !context.mounted) return;

    final repo = ref.read(productRepositoryProvider);
    final userId = ref.read(sessionProvider)?.id;
    try {
      if (action == 'adjust') {
        await repo.adjustBatch(
          batchId: batch.id,
          newQuantity: result.quantity,
          note: result.note,
          userId: userId,
        );
      } else {
        await repo.disposeFromBatch(
          batchId: batch.id,
          quantity: result.quantity,
          note: result.note,
          userId: userId,
        );
      }
      if (context.mounted) showMessage(context, 'Stok diperbarui');
    } on UserRuleException catch (e) {
      if (context.mounted) showMessage(context, e.message, error: true);
    }
  }
}

Future<({int quantity, String note})?> _askQuantity(
  BuildContext context, {
  required String title,
  required String unitName,
  required int initial,
  required String noteHint,
}) {
  final qty = TextEditingController(text: '$initial');
  final note = TextEditingController();
  return showDialog<({int quantity, String note})>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: qty,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(suffixText: unitName),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: note,
            decoration: InputDecoration(
              labelText: 'Alasan',
              hintText: noteHint,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, (
            quantity: parseNumber(qty.text),
            note: note.text,
          )),
          child: const Text('Simpan'),
        ),
      ],
    ),
  );
}

class _MovementsScreen extends ConsumerWidget {
  const _MovementsScreen({required this.summary});

  final ProductSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final movements = ref.watch(movementsProvider(summary.product.id));
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('Riwayat ${summary.product.name}')),
      body: movements.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (list) => list.isEmpty
            ? const Center(child: Text('Belum ada riwayat stok'))
            : ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final m = list[i].movement;
                  final positive = m.quantity > 0;
                  return ListTile(
                    leading: Icon(
                      positive
                          ? Icons.south_west_rounded
                          : Icons.north_east_rounded,
                      color: positive
                          ? const Color(0xFF2E7D32)
                          : theme.colorScheme.error,
                    ),
                    title: Text(m.type.label),
                    subtitle: Text(
                      [
                        formatDateTime(m.createdAt),
                        if (list[i].userName != null) list[i].userName!,
                        if (list[i].batch != null)
                          'ED ${formatExpiry(list[i].batch!.expiryDate)}',
                        if (m.note.isNotEmpty) m.note,
                      ].join(' · '),
                    ),
                    trailing: Text(
                      '${positive ? '+' : '−'}${formatStock(m.quantity.abs(), summary.units)}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: positive
                            ? const Color(0xFF2E7D32)
                            : theme.colorScheme.error,
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
