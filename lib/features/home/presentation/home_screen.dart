import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/common.dart';
import '../../auth/application/session_controller.dart';
import '../../products/presentation/product_list_screen.dart';
import '../../products/presentation/stock_alerts_screen.dart';
import '../../sales/presentation/cashier_screen.dart';
import '../../sales/presentation/sales_history_screen.dart';
import '../../settings/data/settings_repository.dart';
import '../../settings/presentation/settings_screen.dart';

class _MenuItem {
  const _MenuItem({
    required this.icon,
    required this.label,
    required this.description,
    this.ownerOnly = false,
    this.open,
  });

  final IconData icon;
  final String label;
  final String description;
  final bool ownerOnly;

  /// `null` berarti fitur belum tersedia.
  final WidgetBuilder? open;
}

/// Beranda: menu utama berupa kotak-kotak besar.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  static final _items = <_MenuItem>[
    _MenuItem(
      icon: Icons.point_of_sale_rounded,
      label: 'Kasir',
      description: 'Catat penjualan',
      open: (_) => const CashierScreen(),
    ),
    _MenuItem(
      icon: Icons.receipt_long_rounded,
      label: 'Riwayat',
      description: 'Transaksi per hari',
      open: (_) => const SalesHistoryScreen(),
    ),
    _MenuItem(
      icon: Icons.medication_rounded,
      label: 'Produk',
      description: 'Daftar obat & harga',
      open: (_) => const ProductListScreen(),
    ),
    _MenuItem(
      icon: Icons.inventory_2_rounded,
      label: 'Stok & ED',
      description: 'Stok menipis, kedaluwarsa',
      open: (_) => const StockAlertsScreen(),
    ),
    const _MenuItem(
      icon: Icons.schedule_rounded,
      label: 'Shift',
      description: 'Buka & tutup kasir',
    ),
    const _MenuItem(
      icon: Icons.bar_chart_rounded,
      label: 'Laporan',
      description: 'Penjualan & laba',
      ownerOnly: true,
    ),
    _MenuItem(
      icon: Icons.settings_rounded,
      label: 'Pengaturan',
      description: 'Apotek, pengguna, PIN',
      open: (_) => const SettingsScreen(),
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider);
    final isOwner = ref.watch(isOwnerProvider);
    final storeName = ref.watch(storeProfileProvider).value?.name ?? '';
    final items = _items.where((i) => !i.ownerOnly || isOwner).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(storeName),
        actions: [
          IconButton(
            tooltip: 'Keluar',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () => ref.read(sessionProvider.notifier).signOut(),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final columns = width >= 900 ? 4 : (width >= 560 ? 3 : 2);
            return CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      'Halo, ${user?.name ?? ''}',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  sliver: SliverGrid.count(
                    crossAxisCount: columns,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.05,
                    children: [for (final item in items) _MenuTile(item: item)],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({required this.item});

  final _MenuItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final available = item.open != null;

    return Card(
      child: InkWell(
        onTap: () {
          if (available) {
            Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: item.open!));
          } else {
            showMessage(context, 'Fitur "${item.label}" sedang dibuat');
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: available
                    ? scheme.primaryContainer
                    : scheme.surfaceContainerHighest,
                child: Icon(
                  item.icon,
                  size: 28,
                  color: available
                      ? scheme.onPrimaryContainer
                      : scheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Text(
                item.label,
                style: theme.textTheme.titleLarge,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                available ? item.description : 'Segera hadir',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
