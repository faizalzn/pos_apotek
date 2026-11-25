import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/clock.dart';
import '../../../core/format.dart';
import '../../../core/widgets/common.dart';
import '../../auth/application/session_controller.dart';
import '../data/product_models.dart';
import '../data/product_repository.dart';
import 'barcode_scanner_screen.dart';
import 'product_detail_screen.dart';
import 'product_form_screen.dart';
import 'widgets/product_widgets.dart';

/// Mencocokkan produk dengan kata kunci (nama, kandungan, kategori, barcode).
bool matchesQuery(ProductSummary p, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  final words = q.split(RegExp(r'\s+'));
  final haystack =
      '${p.product.name} ${p.product.genericName} ${p.product.category}'
          .toLowerCase();
  if (words.every(haystack.contains)) return true;
  return p.units.any((u) => u.barcode == query.trim());
}

class ProductListScreen extends ConsumerStatefulWidget {
  const ProductListScreen({
    super.key,
    this.initialFilter = ProductFilter.all,
    this.title = 'Produk',
  });

  final ProductFilter initialFilter;
  final String title;

  @override
  ConsumerState<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends ConsumerState<ProductListScreen> {
  final _search = TextEditingController();
  late ProductFilter _filter = widget.initialFilter;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final code = await scanBarcode(context);
    if (code == null || !mounted) return;
    final found = await ref.read(productRepositoryProvider).findByBarcode(code);
    if (!mounted) return;
    if (found != null) {
      _openDetail(found.product.id);
    } else {
      _search.text = code;
      setState(() {});
      showMessage(context, 'Barcode $code belum terdaftar');
    }
  }

  void _openDetail(String id) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ProductDetailScreen(productId: id),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final isOwner = ref.watch(isOwnerProvider);
    final products = ref.watch(productsProvider);
    final now = ref.watch(clockProvider)();
    final filters = ProductFilter.values
        .where((f) => isOwner || f != ProductFilter.archived)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Scan barcode',
            onPressed: _scan,
            icon: const Icon(Icons.qr_code_scanner_rounded),
          ),
        ],
      ),
      floatingActionButton: isOwner
          ? FloatingActionButton.extended(
              onPressed: () => openNewProduct(context),
              icon: const Icon(Icons.add),
              label: const Text('Tambah produk'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              key: const Key('product-search'),
              controller: _search,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Cari nama, kandungan, atau barcode',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Hapus pencarian',
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(_search.clear),
                      ),
              ),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final f in filters)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text(f.label),
                      selected: _filter == f,
                      onSelected: (_) => setState(() => _filter = f),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: products.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Gagal memuat produk: $e')),
              data: (all) {
                final list = all
                    .where((p) => _filter.matches(p, now))
                    .where((p) => matchesQuery(p, _search.text))
                    .toList();
                if (list.isEmpty) {
                  return _EmptyState(
                    hasProducts: all.isNotEmpty,
                    isOwner: isOwner,
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) => _ProductTile(
                    summary: list[i],
                    now: now,
                    onTap: () => _openDetail(list[i].product.id),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Membuka formulir produk baru, lalu menawarkan tambah stok.
Future<void> openNewProduct(BuildContext context) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ProductFormScreen()),
    );

class _ProductTile extends StatelessWidget {
  const _ProductTile({
    required this.summary,
    required this.now,
    required this.onTap,
  });

  final ProductSummary summary;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = summary.product;
    final warnings = productWarnings(summary, now);
    final base = summary.baseUnit;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ProductPhoto(photoFile: p.photoFile, drugClass: p.drugClass),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.name,
                    style: theme.textTheme.titleMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (p.genericName.isNotEmpty)
                    Text(
                      p.genericName,
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      DrugClassBadge(p.drugClass, compact: true),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Stok: ${formatStock(summary.stock, summary.units)}',
                          style: theme.textTheme.bodyMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (warnings.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 4, children: warnings),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatRupiah(base.sellPrice),
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: theme.colorScheme.primary),
                ),
                Text('/ ${base.name}', style: theme.textTheme.bodySmall),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasProducts, required this.isOwner});

  final bool hasProducts;
  final bool isOwner;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasProducts ? Icons.search_off_rounded : Icons.medication_outlined,
              size: 56,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              hasProducts ? 'Tidak ada produk yang cocok' : 'Belum ada produk',
              style: theme.textTheme.titleMedium,
            ),
            if (!hasProducts && isOwner) ...[
              const SizedBox(height: 4),
              const Text(
                'Tekan "Tambah produk" untuk memasukkan obat pertama.',
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
