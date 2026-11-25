import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/format.dart';
import '../../data/photo_store.dart';
import '../../data/product_models.dart';

/// Warna penanda golongan obat, mengikuti logo di kemasan.
Color drugClassColor(DrugClass c) => switch (c) {
      DrugClass.bebas => const Color(0xFF2E7D32),
      DrugClass.bebasTerbatas => const Color(0xFF1565C0),
      DrugClass.keras => const Color(0xFFC62828),
      DrugClass.narkotikaPsikotropika => const Color(0xFF6A1B9A),
      DrugClass.nonObat => const Color(0xFF616161),
    };

/// Lencana kecil golongan obat (lingkaran berwarna + nama).
class DrugClassBadge extends StatelessWidget {
  const DrugClassBadge(this.drugClass, {super.key, this.compact = false});

  final DrugClass drugClass;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = drugClassColor(drugClass);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: drugClass == DrugClass.nonObat ? null : color,
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
          ),
        ),
        if (!compact) ...[
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              drugClass.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ],
    );
  }
}

/// Lencana status (Hampir ED, Stok menipis, ...).
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
}

const expiredColor = Color(0xFFC62828);
const soonColor = Color(0xFFE65100);
const lowStockColor = Color(0xFFB26A00);

/// Lencana-lencana peringatan sebuah produk.
List<Widget> productWarnings(ProductSummary p, DateTime now) => [
      if (p.expiryStatus(now) == ExpiryStatus.expired)
        const StatusChip(
          label: 'Ada yang kedaluwarsa',
          color: expiredColor,
          icon: Icons.error_outline,
        )
      else if (p.expiryStatus(now) == ExpiryStatus.soon)
        StatusChip(
          label: 'ED ${formatExpiry(p.nearestExpiry)}',
          color: soonColor,
          icon: Icons.schedule,
        ),
      if (p.isOutOfStock)
        const StatusChip(label: 'Habis', color: expiredColor)
      else if (p.isLowStock)
        const StatusChip(
          label: 'Stok menipis',
          color: lowStockColor,
          icon: Icons.trending_down,
        ),
    ];

/// Foto produk, atau ikon pengganti bila belum ada foto.
class ProductPhoto extends ConsumerWidget {
  const ProductPhoto({
    super.key,
    required this.photoFile,
    required this.drugClass,
    this.size = 56,
    this.radius = 12,
  });

  final String? photoFile;
  final DrugClass drugClass;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final store = ref.watch(photoStoreProvider).value;
    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: drugClassColor(drugClass).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(
        drugClass == DrugClass.nonObat
            ? Icons.inventory_2_outlined
            : Icons.medication_outlined,
        size: size * 0.5,
        color: drugClassColor(drugClass),
      ),
    );
    if (photoFile == null || store == null) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.file(
        store.fileOf(photoFile!),
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
        errorBuilder: (_, _, _) => placeholder,
        frameBuilder: (context, child, frame, wasSync) => frame == null && !wasSync
            ? Container(
                width: size,
                height: size,
                color: scheme.surfaceContainerHighest,
              )
            : child,
      ),
    );
  }
}

/// Isian bulan & tahun kedaluwarsa (sesuai yang tertera di kemasan).
/// Mengembalikan hari terakhir bulan tersebut.
Future<DateTime?> pickExpiryMonth(
  BuildContext context, {
  DateTime? initial,
}) {
  final now = DateTime.now();
  var year = initial?.year ?? now.year + 1;
  var month = initial?.month ?? now.month;
  return showDialog<DateTime>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final scheme = Theme.of(context).colorScheme;
        return AlertDialog(
          title: const Text('Tanggal kedaluwarsa'),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      tooltip: 'Tahun sebelumnya',
                      onPressed: () => setState(() => year--),
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Text(
                      '$year',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    IconButton(
                      tooltip: 'Tahun berikutnya',
                      onPressed: () => setState(() => year++),
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                GridView.count(
                  crossAxisCount: 4,
                  shrinkWrap: true,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.6,
                  children: [
                    for (var m = 1; m <= 12; m++)
                      Material(
                        color: m == month
                            ? scheme.primary
                            : scheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(10),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => setState(() => month = m),
                          child: Center(
                            child: Text(
                              monthNames[m - 1].substring(0, 3),
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: m == month ? scheme.onPrimary : null,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, endOfMonth(year, month)),
              child: Text('${monthNames[month - 1]} $year'),
            ),
          ],
        );
      },
    ),
  );
}
