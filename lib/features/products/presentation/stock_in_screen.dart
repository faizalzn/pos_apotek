import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/database/app_database.dart';
import '../../../core/format.dart';
import '../../../core/widgets/common.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/data/user_repository.dart' show UserRuleException;
import '../data/product_models.dart';
import '../data/product_repository.dart';
import 'widgets/product_widgets.dart';

/// Mencatat stok masuk (barang datang dari distributor).
class StockInScreen extends ConsumerStatefulWidget {
  const StockInScreen({super.key, required this.productId});

  final String productId;

  @override
  ConsumerState<StockInScreen> createState() => _StockInScreenState();
}

class _StockInScreenState extends ConsumerState<StockInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _qty = TextEditingController(text: '1');
  final _batch = TextEditingController();
  final _cost = TextEditingController();
  final _note = TextEditingController();
  String? _unitId;
  DateTime? _expiry;
  bool _noExpiry = false;
  bool _saving = false;
  String? _expiryError;

  @override
  void dispose() {
    for (final c in [_qty, _batch, _cost, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  ProductUnit _selectedUnit(ProductSummary p) =>
      p.units.where((u) => u.id == _unitId).firstOrNull ?? p.units.last;

  ExpiryStatus _expiryStatus(ProductSummary p) =>
      expiryStatusOf(_expiry, DateTime.now(), windowDays: p.nearExpiryDays);

  Future<void> _pickExpiry() async {
    final picked = await pickExpiryMonth(context, initial: _expiry);
    if (picked != null) {
      setState(() {
        _expiry = picked;
        _expiryError = null;
      });
    }
  }

  Future<void> _save(ProductSummary p) async {
    final formOk = _formKey.currentState!.validate();
    if (_expiry == null && !_noExpiry) {
      setState(() => _expiryError = 'Pilih bulan & tahun kedaluwarsa');
    }
    if (!formOk || (_expiry == null && !_noExpiry)) return;

    final isOwner = ref.read(isOwnerProvider);
    final unit = _selectedUnit(p);
    setState(() => _saving = true);
    try {
      await ref
          .read(productRepositoryProvider)
          .receiveStock(
            productId: p.product.id,
            unit: unit,
            quantity: parseNumber(_qty.text),
            expiryDate: _noExpiry ? null : _expiry,
            batchNumber: _batch.text,
            costPerSelectedUnit: isOwner && _cost.text.trim().isNotEmpty
                ? parseNumber(_cost.text).toDouble()
                : null,
            userId: ref.read(sessionProvider)?.id,
            note: _note.text,
          );
      if (!mounted) return;
      showMessage(context, 'Stok ${p.product.name} bertambah');
      Navigator.pop(context);
    } on UserRuleException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final product = ref.watch(productProvider(widget.productId));
    return Scaffold(
      appBar: AppBar(title: const Text('Tambah Stok')),
      body: product.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (p) => p == null
            ? const Center(child: Text('Produk tidak ditemukan'))
            : _form(context, p),
      ),
    );
  }

  Widget _form(BuildContext context, ProductSummary p) {
    final theme = Theme.of(context);
    final isOwner = ref.watch(isOwnerProvider);
    final unit = _selectedUnit(p);
    final qty = parseNumber(_qty.text);
    final base = p.baseUnit;

    return SafeArea(
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            ContentWidth(
              maxWidth: 560,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: ProductPhoto(
                      photoFile: p.product.photoFile,
                      drugClass: p.product.drugClass,
                    ),
                    title: Text(
                      p.product.name,
                      style: theme.textTheme.titleMedium,
                    ),
                    subtitle: Text(
                      'Stok sekarang: ${formatStock(p.stock, p.units)}',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Satuan yang diterima',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final u in p.units.reversed)
                        ChoiceChip(
                          label: Text(
                            u.multiplier == 1
                                ? u.name
                                : '${u.name} (isi ${u.multiplier})',
                          ),
                          selected: u.id == unit.id,
                          onSelected: (_) => setState(() => _unitId = u.id),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      IconButton.filledTonal(
                        tooltip: 'Kurangi',
                        onPressed: qty > 1
                            ? () => setState(() => _qty.text = '${qty - 1}')
                            : null,
                        icon: const Icon(Icons.remove),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          key: const Key('stock-qty'),
                          controller: _qty,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            labelText: 'Jumlah',
                            suffixText: unit.name,
                          ),
                          validator: (v) =>
                              parseNumber(v ?? '') < 1 ? 'Minimal 1' : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        tooltip: 'Tambah',
                        onPressed: () =>
                            setState(() => _qty.text = '${qty + 1}'),
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                  if (unit.multiplier > 1 && qty > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '= ${formatNumber(qty * unit.multiplier)} ${base.name}',
                        style: theme.textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  const SizedBox(height: 20),
                  Text(
                    'Tanggal kedaluwarsa (ED)',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    key: const Key('pick-expiry'),
                    onPressed: _noExpiry ? null : _pickExpiry,
                    icon: const Icon(Icons.event_outlined),
                    label: Text(
                      _expiry == null
                          ? 'Pilih bulan & tahun'
                          : '${monthNames[_expiry!.month - 1]} ${_expiry!.year}',
                    ),
                  ),
                  if (_expiryError != null && !_noExpiry)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, left: 12),
                      child: Text(
                        _expiryError!,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                  if (_expiry != null &&
                      !_noExpiry &&
                      _expiryStatus(p) != ExpiryStatus.ok)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: StatusChip(
                        label: _expiryStatus(p) == ExpiryStatus.expired
                            ? 'Tanggal ini sudah lewat — periksa kembali'
                            : 'ED kurang dari ${nearExpiryLabel(p.nearExpiryDays)} lagi',
                        color: soonColor,
                        icon: Icons.warning_amber_rounded,
                      ),
                    ),
                  CheckboxListTile(
                    value: _noExpiry,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: (v) => setState(() => _noExpiry = v ?? false),
                    title: const Text(
                      'Barang ini tidak punya tanggal kedaluwarsa',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _batch,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'No. batch (opsional)',
                      hintText:
                          'Tertulis "Batch" / "Lot" / "No. Reg" di kemasan',
                    ),
                  ),
                  if (isOwner) ...[
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _cost,
                      keyboardType: TextInputType.number,
                      inputFormatters: [ThousandsInputFormatter()],
                      decoration: InputDecoration(
                        labelText: 'Harga beli per ${unit.name} (opsional)',
                        prefixText: 'Rp ',
                        helperText: 'Dipakai untuk menghitung laba',
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _note,
                    decoration: const InputDecoration(
                      labelText: 'Catatan (opsional)',
                      hintText: 'mis. nama distributor / no. faktur',
                    ),
                  ),
                  const SizedBox(height: 28),
                  FilledButton(
                    onPressed: _saving ? null : () => _save(p),
                    child: const Text('Simpan stok'),
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
