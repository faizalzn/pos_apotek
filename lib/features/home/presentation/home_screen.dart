import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/clock.dart';
import '../../../core/format.dart';
import '../../../core/widgets/common.dart';
import '../../auth/application/session_controller.dart';
import '../../backup/data/backup_service.dart';
import '../../backup/presentation/backup_screen.dart';
import '../../products/data/product_repository.dart';
import '../../products/presentation/product_list_screen.dart';
import '../../products/presentation/stock_alerts_screen.dart';
import '../../sales/presentation/cashier_screen.dart';
import '../../sales/presentation/sales_history_screen.dart';
import '../../settings/data/settings_repository.dart';
import '../../reports/presentation/reports_screen.dart';
import '../../settings/presentation/settings_screen.dart';
import '../../shift/data/shift_service.dart';
import '../../shift/presentation/shift_screen.dart';

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
    _MenuItem(
      icon: Icons.schedule_rounded,
      label: 'Shift',
      description: 'Buka & tutup, kas laci',
      open: (_) => const ShiftScreen(),
    ),
    _MenuItem(
      icon: Icons.bar_chart_rounded,
      label: 'Laporan',
      description: 'Penjualan & laba',
      ownerOnly: true,
      open: (_) => const ReportsScreen(),
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
            onPressed: () => _signOut(context, ref),
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
                const SliverToBoxAdapter(child: _ShiftStatus()),
                const SliverToBoxAdapter(child: _BackupReminder()),
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

/// Keluar; bila shift milik pengguna ini masih terbuka, tawarkan menutupnya.
Future<void> _signOut(BuildContext context, WidgetRef ref) async {
  final me = ref.read(sessionProvider);
  final shift = await ref.read(shiftServiceProvider).getOpen();
  if (!context.mounted) return;
  if (shift != null && shift.openedBy == me?.id) {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Shift Anda masih terbuka'),
        content: const Text(
          'Bila sudah selesai jaga, tutup shift dulu dan hitung uang di laci '
          'agar serah terima jelas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'logout'),
            child: const Text('Keluar saja'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'close'),
            child: const Text('Tutup shift'),
          ),
        ],
      ),
    );
    if (!context.mounted || choice == null) return;
    if (choice == 'close') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => CloseShiftScreen(shiftId: shift.id)),
      );
      return;
    }
  }
  ref.read(sessionProvider.notifier).signOut();
}

/// Status shift di beranda.
class _ShiftStatus extends ConsumerWidget {
  const _ShiftStatus();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = ref.watch(openShiftProvider);
    final theme = Theme.of(context);
    final shift = open.value;
    if (!open.hasValue) return const SizedBox.shrink();
    final summary = shift == null ? null : ref.watch(shiftSummaryProvider(shift.id)).value;
    String two(int n) => n.toString().padLeft(2, '0');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Card(
        color: shift == null ? theme.colorScheme.surfaceContainerHigh : theme.colorScheme.primaryContainer,
        child: ListTile(
          key: const Key('shift-status'),
          leading: Icon(shift == null ? Icons.lock_clock_outlined : Icons.lock_open_rounded),
          title: Text(
            shift == null
                ? 'Shift belum dibuka'
                : 'Shift ${summary?.openedByName ?? ''} · sejak '
                    '${two(shift.openedAt.hour)}.${two(shift.openedAt.minute)}',
          ),
          subtitle: Text(
            shift == null
                ? 'Ketuk untuk membuka shift'
                : '${summary?.saleCount ?? 0} transaksi · ${formatRupiah(summary?.totalSales ?? 0)}',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const ShiftScreen()),
          ),
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

/// Menjalankan cadangan harian otomatis, dan (untuk Pemilik) mengingatkan
/// bila sudah 7 hari tidak backup ke luar HP.
class _BackupReminder extends ConsumerStatefulWidget {
  const _BackupReminder();

  @override
  ConsumerState<_BackupReminder> createState() => _BackupReminderState();
}

class _BackupReminderState extends ConsumerState<_BackupReminder> {
  @override
  void initState() {
    super.initState();
    _runDaily();
  }

  Future<void> _runDaily() async {
    try {
      final service = await ref.read(backupServiceProvider.future);
      if (await service.runDailyBackupIfDue() != null && mounted) {
        ref.invalidate(localBackupsProvider);
      }
    } on Object catch (e) {
      // Cadangan otomatis tidak boleh mengganggu pekerjaan kasir.
      debugPrint('Cadangan harian gagal: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOwner = ref.watch(isOwnerProvider);
    final state = ref.watch(backupStateProvider);
    final hasProducts = ref.watch(productsProvider).value?.isNotEmpty ?? false;
    final now = ref.watch(clockProvider)();
    if (!isOwner || !hasProducts || !state.hasValue || !isExportDue(state.value, now)) {
      return const SizedBox.shrink();
    }
    final last = state.value!.lastExportAt;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Card(
        color: theme.colorScheme.errorContainer,
        child: ListTile(
          key: const Key('backup-reminder'),
          leading: const Icon(Icons.backup_outlined),
          title: Text(
            last == null
                ? 'Data belum pernah di-backup'
                : 'Backup terakhir ${daysAgo(last, now)}',
          ),
          subtitle: const Text('Simpan backup ke Drive/WhatsApp agar data aman'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const BackupScreen()),
          ),
        ),
      ),
    );
  }
}
