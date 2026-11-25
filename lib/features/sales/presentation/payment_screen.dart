import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/database/app_database.dart';
import '../../../core/format.dart';
import '../../../core/widgets/common.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/data/user_repository.dart' show UserRuleException;
import '../application/cart_controller.dart';
import '../data/sale_service.dart';
import 'sale_success_screen.dart';

/// Pilihan uang cepat: uang pas lalu pecahan umum di atas total.
List<int> quickCashOptions(int total) {
  const notes = [1000, 2000, 5000, 10000, 20000, 50000, 100000];
  final options = <int>{};
  for (final n in notes) {
    final rounded = ((total + n - 1) ~/ n) * n;
    if (rounded > total) options.add(rounded);
  }
  for (final n in [50000, 100000]) {
    if (n > total) options.add(n);
  }
  final sorted = options.toList()..sort();
  return sorted.take(4).toList();
}

class PaymentScreen extends ConsumerStatefulWidget {
  const PaymentScreen({super.key});

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  PaymentMethod _method = PaymentMethod.cash;
  final _cash = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _cash.dispose();
    super.dispose();
  }

  Future<void> _complete(Cart cart) async {
    setState(() => _saving = true);
    try {
      final sale = await ref
          .read(saleServiceProvider)
          .complete(
            cart: cart,
            method: _method,
            amountPaid: _method == PaymentMethod.cash
                ? parseNumber(_cash.text)
                : cart.total,
            cashier: ref.read(sessionProvider)!,
          );
      ref.read(cartProvider.notifier).clear();
      if (!mounted) return;
      await Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => SaleSuccessScreen(sale: sale)),
        (route) => route.isFirst,
      );
    } on UserRuleException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final theme = Theme.of(context);
    final total = cart.total;
    final paid = parseNumber(_cash.text);
    final change = paid - total;
    final canPay =
        !_saving &&
        !cart.isEmpty &&
        (_method == PaymentMethod.qris || paid >= total);

    return Scaffold(
      appBar: AppBar(title: const Text('Pembayaran')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            ContentWidth(
              maxWidth: 520,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Total belanja',
                    style: theme.textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    formatRupiah(total),
                    key: const Key('payment-total'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  Text(
                    '${cart.itemCount} barang',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  SegmentedButton<PaymentMethod>(
                    segments: const [
                      ButtonSegment(
                        value: PaymentMethod.cash,
                        label: Text('Tunai'),
                        icon: Icon(Icons.payments_outlined),
                      ),
                      ButtonSegment(
                        value: PaymentMethod.qris,
                        label: Text('QRIS'),
                        icon: Icon(Icons.qr_code_2),
                      ),
                    ],
                    selected: {_method},
                    onSelectionChanged: (s) =>
                        setState(() => _method = s.first),
                  ),
                  const SizedBox(height: 24),
                  if (_method == PaymentMethod.cash) ...[
                    TextField(
                      key: const Key('cash-received'),
                      controller: _cash,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      inputFormatters: [ThousandsInputFormatter()],
                      style: theme.textTheme.headlineSmall,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Uang diterima',
                        prefixText: 'Rp ',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ActionChip(
                          label: const Text('Uang pas'),
                          onPressed: () =>
                              setState(() => _cash.text = formatNumber(total)),
                        ),
                        for (final v in quickCashOptions(total))
                          ActionChip(
                            label: Text(formatRupiah(v)),
                            onPressed: () =>
                                setState(() => _cash.text = formatNumber(v)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: change >= 0 && _cash.text.isNotEmpty
                            ? theme.colorScheme.primaryContainer
                            : theme.colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          Text(
                            change < 0 && _cash.text.isNotEmpty
                                ? 'Uang kurang'
                                : 'Kembalian',
                            style: theme.textTheme.titleMedium,
                          ),
                          Text(
                            _cash.text.isEmpty
                                ? '-'
                                : formatRupiah(change.abs()),
                            key: const Key('change'),
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: change < 0
                                  ? theme.colorScheme.error
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.qr_code_2,
                                  color: theme.colorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Bayar dengan QRIS',
                                  style: theme.textTheme.titleMedium,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '1. Minta pelanggan scan stiker QRIS apotek.\n'
                              '2. Pelanggan membayar sebesar ${formatRupiah(total)}.\n'
                              '3. Pastikan notifikasi pembayaran sudah masuk di '
                              'aplikasi bank/merchant, lalu tekan tombol di bawah.',
                              style: theme.textTheme.bodyLarge,
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    key: const Key('complete-sale'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(60),
                    ),
                    onPressed: canPay ? () => _complete(cart) : null,
                    icon: const Icon(Icons.check_circle_outline),
                    label: Text(
                      _method == PaymentMethod.qris
                          ? 'Pembayaran sudah masuk'
                          : 'Selesaikan transaksi',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
