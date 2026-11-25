import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/format.dart';
import '../../../core/widgets/common.dart';
import '../../auth/application/session_controller.dart';
import '../../products/presentation/widgets/product_widgets.dart';
import '../application/cart_controller.dart';
import 'payment_screen.dart';

/// Isi keranjang + ringkasan total + tombol Bayar.
class CartView extends ConsumerWidget {
  const CartView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final isOwner = ref.watch(isOwnerProvider);
    final theme = Theme.of(context);

    if (cart.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.shopping_cart_outlined,
                size: 56,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(height: 12),
              const Text('Keranjang kosong', textAlign: TextAlign.center),
              const SizedBox(height: 4),
              Text(
                'Ketuk barang atau scan barcode untuk menambahkan.',
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: cart.lines.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) =>
                _LineTile(index: i, line: cart.lines[i]),
          ),
        ),
        Material(
          elevation: 8,
          color: theme.colorScheme.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (cart.itemDiscount > 0 || cart.discount > 0) ...[
                  _Row('Subtotal', formatRupiah(cart.subtotal)),
                  if (cart.itemDiscount > 0)
                    _Row(
                      'Diskon barang',
                      '−${formatRupiah(cart.itemDiscount)}',
                    ),
                  if (cart.discount > 0)
                    _Row('Diskon total', '−${formatRupiah(cart.discount)}'),
                  const SizedBox(height: 4),
                ],
                Row(
                  children: [
                    Text('Total', style: theme.textTheme.titleLarge),
                    const Spacer(),
                    Text(
                      formatRupiah(cart.total),
                      key: const Key('cart-total'),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                if (isOwner)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => _editTotalDiscount(context, ref, cart),
                      icon: const Icon(Icons.local_offer_outlined, size: 20),
                      label: Text(
                        cart.discount > 0
                            ? 'Ubah diskon total'
                            : 'Diskon total (opsional)',
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  key: const Key('pay'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(60),
                  ),
                  onPressed: () {
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const PaymentScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('Bayar'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _editTotalDiscount(
    BuildContext context,
    WidgetRef ref,
    Cart cart,
  ) async {
    final max = cart.subtotal - cart.itemDiscount;
    final value = await showDiscountDialog(
      context,
      title: 'Diskon total belanja',
      base: max,
      initial: cart.discount,
    );
    if (value != null) ref.read(cartProvider.notifier).setDiscount(value);
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(children: [Text(label), const Spacer(), Text(value)]),
  );
}

class _LineTile extends ConsumerWidget {
  const _LineTile({required this.index, required this.line});

  final int index;
  final CartLine line;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isOwner = ref.watch(isOwnerProvider);
    final notifier = ref.read(cartProvider.notifier);

    void change(int qty) {
      final r = notifier.setQuantity(index, qty);
      if (r case CartChangeNoStock(:final availableBase)) {
        showMessage(
          context,
          'Stok tidak cukup. Sisa ${formatNumber(availableBase)} ${line.baseUnitName}',
          error: true,
        );
      }
    }

    return InkWell(
      onTap: isOwner ? () => _editLine(context, ref) : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(line.productName, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    '${formatRupiah(line.unitPrice)} / ${line.unit.name}'
                    '${line.priceChanged ? ' (harga diubah)' : ''}',
                    style: theme.textTheme.bodySmall,
                  ),
                  if (line.discount > 0)
                    Text(
                      'Diskon −${formatRupiah(line.discount)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  if (line.drugClass.requiresPrescription) ...[
                    const SizedBox(height: 4),
                    const StatusChip(
                      label: 'Perlu resep',
                      color: expiredColor,
                      icon: Icons.assignment_outlined,
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    formatRupiah(line.total),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            IconButton.filledTonal(
              tooltip: line.quantity == 1 ? 'Hapus' : 'Kurangi',
              onPressed: () => change(line.quantity - 1),
              icon: Icon(
                line.quantity == 1 ? Icons.delete_outline : Icons.remove,
              ),
            ),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () async {
                final qty = await _askQuantity(context, line);
                if (qty != null) change(qty);
              },
              child: Container(
                constraints: const BoxConstraints(minWidth: 52),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                child: Column(
                  children: [
                    Text(
                      '${line.quantity}',
                      style: theme.textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    Text(line.unit.name, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ),
            IconButton.filledTonal(
              tooltip: 'Tambah',
              onPressed: () => change(line.quantity + 1),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ),
    );
  }

  Future<int?> _askQuantity(BuildContext context, CartLine line) {
    final controller = TextEditingController(text: '${line.quantity}');
    return showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Jumlah ${line.productName}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(suffixText: line.unit.name),
          onSubmitted: (v) => Navigator.pop(context, parseNumber(v)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, parseNumber(controller.text)),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  /// Pemilik: ubah harga & diskon baris.
  Future<void> _editLine(BuildContext context, WidgetRef ref) async {
    final price = TextEditingController(text: formatNumber(line.unitPrice));
    final result = await showDialog<({int price, int discount})>(
      context: context,
      builder: (context) {
        var discount = line.discount;
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: Text(line.productName),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: price,
                  keyboardType: TextInputType.number,
                  inputFormatters: [ThousandsInputFormatter()],
                  decoration: InputDecoration(
                    labelText: 'Harga per ${line.unit.name}',
                    prefixText: 'Rp ',
                    helperText:
                        'Harga normal ${formatRupiah(line.unit.sellPrice)}',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () async {
                    final v = await showDiscountDialog(
                      context,
                      title: 'Diskon ${line.productName}',
                      base: parseNumber(price.text) * line.quantity,
                      initial: discount,
                    );
                    if (v != null) setState(() => discount = v);
                  },
                  icon: const Icon(Icons.local_offer_outlined),
                  label: Text(
                    discount > 0
                        ? 'Diskon ${formatRupiah(discount)}'
                        : 'Beri diskon (opsional)',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, (
                  price: line.unit.sellPrice,
                  discount: 0,
                )),
                child: const Text('Kembalikan normal'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, (
                  price: parseNumber(price.text),
                  discount: discount,
                )),
                child: const Text('Simpan'),
              ),
            ],
          ),
        );
      },
    );
    if (result == null) return;
    ref
        .read(cartProvider.notifier)
        .updatePricing(
          index,
          unitPrice: result.price,
          discount: result.discount,
        );
  }
}

/// Dialog diskon dalam rupiah atau persen. Mengembalikan nominal rupiah.
Future<int?> showDiscountDialog(
  BuildContext context, {
  required String title,
  required int base,
  required int initial,
}) {
  final controller = TextEditingController(
    text: initial > 0 ? formatNumber(initial) : '',
  );
  var percent = false;
  return showDialog<int>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final raw = parseNumber(controller.text);
        final amount =
            (percent ? (base * raw.clamp(0, 100) / 100).round() : raw).clamp(
              0,
              base,
            );
        return AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Rupiah')),
                  ButtonSegment(value: true, label: Text('Persen')),
                ],
                selected: {percent},
                onSelectionChanged: (s) => setState(() {
                  percent = s.first;
                  controller.clear();
                }),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  if (percent)
                    FilteringTextInputFormatter.digitsOnly
                  else
                    ThousandsInputFormatter(),
                ],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  prefixText: percent ? null : 'Rp ',
                  suffixText: percent ? '%' : null,
                  helperText:
                      'Dari ${formatRupiah(base)} → potongan ${formatRupiah(amount)}',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 0),
              child: const Text('Hapus diskon'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, amount),
              child: const Text('Simpan'),
            ),
          ],
        );
      },
    ),
  );
}
