import 'package:material_ui/material_ui.dart';

import '../../../core/database/app_database.dart';
import '../../../core/format.dart';
import '../../../core/widgets/common.dart';
import '../../receipt/presentation/receipt_actions.dart';
import 'cashier_screen.dart';

/// Konfirmasi setelah transaksi tersimpan.
class SaleSuccessScreen extends StatelessWidget {
  const SaleSuccessScreen({super.key, required this.sale});

  final Sale sale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCash = sale.paymentMethod == PaymentMethod.cash;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ContentWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    size: 88,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Transaksi berhasil',
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    'No. ${sale.number} · ${sale.paymentMethod.label}',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  if (isCash && sale.change > 0) ...[
                    Text(
                      'Kembalian',
                      style: theme.textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    Text(
                      formatRupiah(sale.change),
                      key: const Key('success-change'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Total ${formatRupiah(sale.total)} · Diterima ${formatRupiah(sale.amountPaid)}',
                      textAlign: TextAlign.center,
                    ),
                  ] else
                    Text(
                      formatRupiah(sale.total),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  const SizedBox(height: 32),
                  ReceiptActions(saleId: sale.id, autoPrint: true),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    key: const Key('new-sale'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(60),
                    ),
                    onPressed: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute<void>(
                        builder: (_) => const CashierScreen(),
                      ),
                    ),
                    icon: const Icon(Icons.add_shopping_cart),
                    label: const Text('Transaksi baru'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Kembali ke beranda'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
