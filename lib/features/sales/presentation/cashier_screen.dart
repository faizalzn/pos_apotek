import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/clock.dart';
import '../../../core/database/app_database.dart';
import '../../../core/format.dart';
import '../../../core/widgets/common.dart';
import '../../products/data/product_models.dart';
import '../../products/data/product_repository.dart';
import '../../products/presentation/barcode_scanner_screen.dart';
import '../../products/presentation/product_list_screen.dart' show matchesQuery;
import '../../products/presentation/widgets/product_widgets.dart';
import '../application/cart_controller.dart';
import 'cart_view.dart';

/// Layar kasir: cari/scan barang → keranjang → bayar.
///
/// Di tablet (layar lebar) daftar barang dan keranjang tampil berdampingan;
/// di HP keranjang dibuka dari bilah bawah.
class CashierScreen extends ConsumerStatefulWidget {
  const CashierScreen({super.key});

  @override
  ConsumerState<CashierScreen> createState() => _CashierScreenState();
}

class _CashierScreenState extends ConsumerState<CashierScreen> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// Enter di kolom cari: cocokkan barcode (scanner USB/Bluetooth bekerja
  /// seperti keyboard), atau tambahkan satu-satunya hasil pencarian.
  Future<void> _onSubmitted(String text) async {
    final code = text.trim();
    if (code.isEmpty) return;
    if (await _addByBarcode(code)) {
      _search.clear();
    } else {
      final results = _results(ref.read(productsProvider).value ?? const []);
      if (results.length == 1 && mounted) {
        await addProductToCart(context, ref, results.single);
        _search.clear();
      } else if (results.isEmpty && mounted) {
        showMessage(context, 'Barang "$code" tidak ditemukan');
      }
    }
    setState(() {});
    _searchFocus.requestFocus();
  }

  Future<bool> _addByBarcode(String code) async {
    final found = await ref.read(productRepositoryProvider).findByBarcode(code);
    if (found == null || !found.product.isActive || !mounted) return false;
    final summary = await ref
        .read(productRepositoryProvider)
        .getOne(found.product.id);
    if (summary == null || !mounted) return false;
    addUnitToCart(context, ref, summary, found.unit);
    return true;
  }

  Future<void> _scan() async {
    final code = await scanBarcode(context);
    if (code == null || !mounted) return;
    if (!await _addByBarcode(code) && mounted) {
      showMessage(context, 'Barcode $code belum terdaftar', error: true);
    }
  }

  List<ProductSummary> _results(List<ProductSummary> all) => all
      .where((p) => p.product.isActive)
      .where((p) => matchesQuery(p, _search.text))
      .toList();

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final wide = MediaQuery.sizeOf(context).width >= 840;

    final productPane = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            key: const Key('cashier-search'),
            controller: _search,
            focusNode: _searchFocus,
            autofocus: wide,
            onChanged: (_) => setState(() {}),
            onSubmitted: _onSubmitted,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Cari obat atau scan barcode',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Hapus pencarian',
                      onPressed: () => setState(_search.clear),
                      icon: const Icon(Icons.close),
                    ),
            ),
          ),
        ),
        Expanded(child: _ProductResults(results: _results)),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kasir'),
        actions: [
          IconButton(
            tooltip: 'Scan barcode',
            onPressed: _scan,
            icon: const Icon(Icons.qr_code_scanner_rounded),
          ),
          if (!cart.isEmpty)
            IconButton(
              tooltip: 'Kosongkan keranjang',
              onPressed: () async {
                final ok = await confirm(
                  context,
                  title: 'Kosongkan keranjang?',
                  message: 'Semua barang di keranjang akan dihapus.',
                  confirmLabel: 'Kosongkan',
                  destructive: true,
                );
                if (ok) ref.read(cartProvider.notifier).clear();
              },
              icon: const Icon(Icons.remove_shopping_cart_outlined),
            ),
        ],
      ),
      body: SafeArea(
        child: wide
            ? Row(
                children: [
                  Expanded(flex: 3, child: productPane),
                  const VerticalDivider(width: 1),
                  const Expanded(flex: 2, child: CartView()),
                ],
              )
            : productPane,
      ),
      bottomNavigationBar: wide || cart.isEmpty ? null : _CartBar(cart: cart),
    );
  }
}

class _ProductResults extends ConsumerWidget {
  const _ProductResults({required this.results});

  final List<ProductSummary> Function(List<ProductSummary>) results;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(productsProvider);
    final cart = ref.watch(cartProvider);
    final now = ref.watch(clockProvider)();
    final theme = Theme.of(context);

    return products.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (all) {
        final list = results(all);
        if (list.isEmpty) {
          return Center(
            child: Text(
              all.isEmpty
                  ? 'Belum ada produk. Tambahkan dulu di menu Produk.'
                  : 'Tidak ada barang yang cocok',
              textAlign: TextAlign.center,
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.only(bottom: 16),
          itemCount: list.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final p = list[i];
            final available =
                p.sellableStock(now) - cart.baseQuantityOf(p.product.id);
            final soldOut = available <= 0;
            final inCart = cart.baseQuantityOf(p.product.id);
            return ListTile(
              enabled: !soldOut,
              onTap: () => addProductToCart(context, ref, p),
              leading: ProductPhoto(
                photoFile: p.product.photoFile,
                drugClass: p.product.drugClass,
                size: 48,
              ),
              title: Text(
                p.product.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                soldOut && inCart == 0
                    ? 'Stok habis'
                    : 'Sisa ${formatStock(available, p.units)}',
                style: TextStyle(
                  color: soldOut ? theme.colorScheme.error : null,
                ),
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatRupiah(p.baseUnit.sellPrice),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  Text(
                    '/ ${p.baseUnit.name}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// Bilah bawah (HP): ringkasan keranjang + tombol buka keranjang.
class _CartBar extends StatelessWidget {
  const _CartBar({required this.cart});

  final Cart cart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton(
          key: const Key('open-cart'),
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: const Text('Keranjang')),
                  body: const SafeArea(child: CartView()),
                ),
              ),
            );
          },
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64)),
          child: Row(
            children: [
              Badge(
                label: Text('${cart.itemCount}'),
                child: const Icon(Icons.shopping_cart_outlined),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Text(
                  'Keranjang',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                formatRupiah(cart.total),
                style: theme.textTheme.titleLarge?.copyWith(
                  color: theme.colorScheme.onPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mengetuk produk: satu satuan → langsung masuk; beberapa satuan → pilih dulu.
Future<void> addProductToCart(
  BuildContext context,
  WidgetRef ref,
  ProductSummary product,
) async {
  if (product.units.length == 1) {
    addUnitToCart(context, ref, product, product.baseUnit);
    return;
  }
  final now = ref.read(clockProvider)();
  final available =
      product.sellableStock(now) -
      ref.read(cartProvider).baseQuantityOf(product.product.id);
  final unit = await showModalBottomSheet<ProductUnit>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      final theme = Theme.of(context);
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                product.product.name,
                style: theme.textTheme.titleLarge,
              ),
              subtitle: Text('Sisa ${formatStock(available, product.units)}'),
            ),
            const Divider(),
            for (final u in product.units)
              ListTile(
                enabled: u.multiplier <= available,
                onTap: () => Navigator.pop(context, u),
                leading: const Icon(Icons.add_circle_outline),
                title: Text(u.name, style: theme.textTheme.titleMedium),
                subtitle: u.multiplier > 1
                    ? Text('isi ${u.multiplier} ${product.baseUnit.name}')
                    : null,
                trailing: Text(
                  formatRupiah(u.sellPrice),
                  style: theme.textTheme.titleMedium,
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
  if (unit != null && context.mounted) {
    addUnitToCart(context, ref, product, unit);
  }
}

void addUnitToCart(
  BuildContext context,
  WidgetRef ref,
  ProductSummary product,
  ProductUnit unit,
) {
  final result = ref.read(cartProvider.notifier).add(product, unit);
  switch (result) {
    case CartChangeOk():
      if (product.product.drugClass.requiresPrescription) {
        showMessage(
          context,
          '${product.product.name} adalah ${product.product.drugClass.label.toLowerCase()} '
          '— pastikan pelanggan membawa resep dokter.',
        );
      } else {
        showMessage(
          context,
          '${product.product.name} (${unit.name}) ditambahkan',
          duration: const Duration(milliseconds: 1500),
        );
      }
    case CartChangeNoStock(:final availableBase):
      showMessage(
        context,
        availableBase <= 0
            ? 'Stok ${product.product.name} sudah habis'
            : 'Stok tidak cukup. Sisa ${formatStock(availableBase, product.units)}',
        error: true,
      );
  }
}
