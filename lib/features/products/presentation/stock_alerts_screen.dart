import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/clock.dart';
import '../data/product_models.dart';
import '../data/product_repository.dart';
import 'product_list_screen.dart';
import 'widgets/product_widgets.dart';

/// Ringkasan peringatan stok & kedaluwarsa (menu "Stok & ED").
class StockAlertsScreen extends ConsumerWidget {
  const StockAlertsScreen({super.key});

  static const _items = [
    (ProductFilter.expired, Icons.error_outline, expiredColor,
        'Segera keluarkan dari rak'),
    (ProductFilter.nearExpiry, Icons.schedule, soonColor,
        'Kedaluwarsa dalam 3 bulan — jual lebih dulu'),
    (ProductFilter.lowStock, Icons.trending_down, lowStockColor,
        'Saatnya pesan ulang'),
    (ProductFilter.outOfStock, Icons.remove_shopping_cart_outlined, expiredColor,
        'Stok kosong'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(productsProvider);
    final now = ref.watch(clockProvider)();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Stok & Kedaluwarsa')),
      body: products.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (all) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final (filter, icon, color, hint) in _items)
              Builder(
                builder: (context) {
                  final count = all.where((p) => filter.matches(p, now)).length;
                  return Card(
                    child: ListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      leading: CircleAvatar(
                        backgroundColor: color.withValues(alpha: 0.12),
                        child: Icon(icon, color: color),
                      ),
                      title: Text(filter.label, style: theme.textTheme.titleMedium),
                      subtitle: Text(hint),
                      trailing: Text(
                        '$count',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: count > 0 ? color : theme.colorScheme.outline,
                        ),
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ProductListScreen(
                            initialFilter: filter,
                            title: filter.label,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
