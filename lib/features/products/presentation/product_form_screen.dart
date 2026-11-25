import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/database/app_database.dart';
import '../../../core/format.dart';
import '../../../core/widgets/common.dart';
import '../../auth/data/user_repository.dart' show UserRuleException;
import '../data/photo_store.dart';
import '../data/product_models.dart';
import '../data/product_repository.dart';
import 'barcode_scanner_screen.dart';
import 'stock_in_screen.dart';
import 'widgets/product_widgets.dart';

const _baseUnitSuggestions = [
  'Tablet', 'Kapsul', 'Kaplet', 'Botol', 'Tube', 'Sachet', 'Pcs', //
];
const _packUnitSuggestions = ['Strip', 'Blister', 'Box', 'Dus', 'Lusin'];

class _UnitRow {
  _UnitRow({this.id, String name = '', int? multiplier, int? price, String? barcode})
      : name = TextEditingController(text: name),
        multiplier = TextEditingController(text: multiplier?.toString() ?? ''),
        price = TextEditingController(
          text: price == null ? '' : formatNumber(price),
        ),
        barcode = TextEditingController(text: barcode ?? '');

  final String? id;
  final TextEditingController name;
  final TextEditingController multiplier;
  final TextEditingController price;
  final TextEditingController barcode;

  void dispose() {
    name.dispose();
    multiplier.dispose();
    price.dispose();
    barcode.dispose();
  }
}

/// Formulir tambah/ubah produk.
class ProductFormScreen extends ConsumerStatefulWidget {
  const ProductFormScreen({super.key, this.existing});

  /// `null` untuk produk baru.
  final ProductSummary? existing;

  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _generic = TextEditingController();
  final _category = TextEditingController();
  final _categoryFocus = FocusNode();
  final _minStock = TextEditingController();
  DrugClass _drugClass = DrugClass.bebas;
  late final _UnitRow _base;
  final _packs = <_UnitRow>[];

  String? _originalPhoto;
  String? _photo;
  bool _saved = false;
  bool _saving = false;
  List<String> _categories = const [];
  PhotoStore? _store;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e == null) {
      _base = _UnitRow(name: 'Tablet', multiplier: 1);
    } else {
      final p = e.product;
      _name.text = p.name;
      _generic.text = p.genericName;
      _category.text = p.category;
      _drugClass = p.drugClass;
      _minStock.text = p.minStock == 0 ? '' : '${p.minStock}';
      _originalPhoto = _photo = p.photoFile;
      final base = e.baseUnit;
      _base = _UnitRow(
        id: base.id,
        name: base.name,
        multiplier: 1,
        price: base.sellPrice,
        barcode: base.barcode,
      );
      for (final u in e.units.skip(1)) {
        _packs.add(
          _UnitRow(
            id: u.id,
            name: u.name,
            multiplier: u.multiplier,
            price: u.sellPrice,
            barcode: u.barcode,
          ),
        );
      }
    }
    ref.read(photoStoreProvider.future).then((s) => _store = s);
    ref.read(productRepositoryProvider).categories().then((c) {
      if (mounted) setState(() => _categories = c);
    });
  }

  @override
  void dispose() {
    // Foto baru yang tidak jadi disimpan → hapus agar tidak menumpuk.
    if (!_saved && _photo != _originalPhoto) {
      _store?.delete(_photo);
    }
    for (final c in [_name, _generic, _category, _minStock]) {
      c.dispose();
    }
    _categoryFocus.dispose();
    _base.dispose();
    for (final r in _packs) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<ImageSource?>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Ambil foto dengan kamera'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Pilih dari galeri'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            if (_photo != null)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Hapus foto'),
                onTap: () {
                  Navigator.pop(context);
                  _setPhoto(null);
                },
              ),
          ],
        ),
      ),
    );
    if (source == null) return;
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );
      if (picked == null) return;
      final store = await ref.read(photoStoreProvider.future);
      _store = store;
      final name = await store.save(picked.path);
      _setPhoto(name);
    } on PlatformException catch (e) {
      if (mounted) {
        showMessage(context, 'Foto tidak bisa diambil: ${e.message}', error: true);
      }
    }
  }

  void _setPhoto(String? name) {
    final previous = _photo;
    setState(() => _photo = name);
    // Hapus foto sementara sebelumnya (bukan foto asli yang tersimpan).
    if (previous != null && previous != _originalPhoto) {
      _store?.delete(previous);
    }
  }

  Future<void> _scanInto(TextEditingController controller) async {
    final code = await scanBarcode(context);
    if (code != null) setState(() => controller.text = code);
  }

  ProductInput _input() => ProductInput(
        name: _name.text,
        genericName: _generic.text,
        category: _category.text,
        drugClass: _drugClass,
        minStock: parseNumber(_minStock.text),
        photoFile: _photo,
        units: [
          UnitInput(
            id: _base.id,
            name: _base.name.text,
            multiplier: 1,
            sellPrice: parseNumber(_base.price.text),
            barcode: _base.barcode.text,
          ),
          for (final r in _packs)
            UnitInput(
              id: r.id,
              name: r.name.text,
              multiplier: parseNumber(r.multiplier.text),
              sellPrice: parseNumber(r.price.text),
              barcode: r.barcode.text,
            ),
        ],
      );

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final repo = ref.read(productRepositoryProvider);
    try {
      if (_isEdit) {
        await repo.update(widget.existing!.product.id, _input());
        _saved = true;
        if (_originalPhoto != null && _originalPhoto != _photo) {
          await _store?.delete(_originalPhoto);
        }
        if (!mounted) return;
        showMessage(context, 'Perubahan tersimpan');
        Navigator.pop(context);
      } else {
        final product = await repo.create(_input());
        _saved = true;
        if (!mounted) return;
        final addStock = await confirm(
          context,
          title: 'Produk tersimpan',
          message: 'Tambah stok "${product.name}" sekarang?',
          confirmLabel: 'Tambah stok',
        );
        if (!mounted) return;
        if (addStock) {
          await Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => StockInScreen(productId: product.id),
            ),
          );
        } else {
          Navigator.pop(context);
        }
      }
    } on UserRuleException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseName =
        _base.name.text.trim().isEmpty ? 'satuan terkecil' : _base.name.text.trim();

    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Ubah Produk' : 'Tambah Produk')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              ContentWidth(
                maxWidth: 640,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: _pickPhoto,
                        child: Stack(
                          children: [
                            ProductPhoto(
                              photoFile: _photo,
                              drugClass: _drugClass,
                              size: 120,
                              radius: 20,
                            ),
                            Positioned(
                              right: 6,
                              bottom: 6,
                              child: CircleAvatar(
                                radius: 18,
                                backgroundColor: theme.colorScheme.primary,
                                child: Icon(
                                  Icons.photo_camera_outlined,
                                  size: 20,
                                  color: theme.colorScheme.onPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Center(
                      child: TextButton(
                        onPressed: _pickPhoto,
                        child: Text(_photo == null ? 'Tambah foto (opsional)' : 'Ganti foto'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      key: const Key('product-name'),
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Nama produk *',
                        hintText: 'mis. Paracetamol 500 mg',
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Nama produk wajib diisi'
                          : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _generic,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Kandungan / nama generik',
                        hintText: 'Membantu pencarian, mis. Paracetamol',
                      ),
                    ),
                    const SizedBox(height: 14),
                    RawAutocomplete<String>(
                      textEditingController: _category,
                      focusNode: _categoryFocus,
                      optionsBuilder: (value) => _categories.where(
                        (c) =>
                            c.toLowerCase().contains(value.text.toLowerCase()) &&
                            c != value.text,
                      ),
                      fieldViewBuilder: (context, controller, focus, onSubmit) =>
                          TextFormField(
                        controller: controller,
                        focusNode: focus,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Kategori',
                          hintText: 'mis. Demam & Nyeri, Vitamin, Batuk',
                        ),
                      ),
                      optionsViewBuilder: (context, onSelected, options) => Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          elevation: 4,
                          borderRadius: BorderRadius.circular(12),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 220, maxWidth: 400),
                            child: ListView(
                              shrinkWrap: true,
                              children: [
                                for (final o in options)
                                  ListTile(title: Text(o), onTap: () => onSelected(o)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<DrugClass>(
                      initialValue: _drugClass,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Golongan'),
                      items: [
                        for (final c in DrugClass.values)
                          DropdownMenuItem(value: c, child: DrugClassBadge(c)),
                      ],
                      onChanged: (c) => setState(() => _drugClass = c!),
                    ),
                    if (_drugClass.requiresPrescription)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Kasir akan diingatkan bahwa obat ini perlu resep dokter.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    const SizedBox(height: 28),
                    Text('Satuan & harga jual', style: theme.textTheme.titleLarge),
                    const SizedBox(height: 4),
                    const Text(
                      'Mulai dari satuan terkecil yang bisa dijual eceran. '
                      'Stok dihitung dalam satuan ini.',
                    ),
                    const SizedBox(height: 12),
                    _unitCard(_base, isBase: true, baseName: baseName),
                    for (final r in _packs)
                      _unitCard(r, isBase: false, baseName: baseName),
                    const SizedBox(height: 4),
                    OutlinedButton.icon(
                      onPressed: () => setState(() => _packs.add(_UnitRow())),
                      icon: const Icon(Icons.add),
                      label: const Text('Tambah satuan kemasan (Strip, Box, ...)'),
                    ),
                    const SizedBox(height: 28),
                    TextFormField(
                      controller: _minStock,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: 'Peringatan stok menipis',
                        hintText: 'Kosongkan bila tidak perlu',
                        suffixText: baseName,
                        helperText:
                            'Muncul peringatan bila stok sama atau kurang dari angka ini',
                      ),
                    ),
                    const SizedBox(height: 28),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: Text(_isEdit ? 'Simpan perubahan' : 'Simpan produk'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _unitCard(_UnitRow row, {required bool isBase, required String baseName}) {
    final theme = Theme.of(context);
    final suggestions = isBase ? _baseUnitSuggestions : _packUnitSuggestions;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    isBase ? 'Satuan terkecil' : 'Satuan kemasan',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                if (!isBase)
                  IconButton(
                    tooltip: 'Hapus satuan',
                    onPressed: () => setState(() {
                      _packs.remove(row);
                      row.dispose();
                    }),
                    icon: const Icon(Icons.close),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final s in suggestions)
                    ChoiceChip(
                      label: Text(s),
                      selected: row.name.text == s,
                      onSelected: (_) => setState(() => row.name.text = s),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: row.name,
                    textCapitalization: TextCapitalization.words,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(labelText: 'Nama satuan *'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
                  ),
                  if (!isBase) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: row.multiplier,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: 'Isi *',
                        prefixText: '1 ${row.name.text.trim().isEmpty ? 'kemasan' : row.name.text.trim()} = ',
                        suffixText: baseName,
                      ),
                      validator: (v) =>
                          parseNumber(v ?? '') < 2 ? 'Isi minimal 2' : null,
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: row.price,
                    keyboardType: TextInputType.number,
                    inputFormatters: [ThousandsInputFormatter()],
                    decoration: const InputDecoration(
                      labelText: 'Harga jual *',
                      prefixText: 'Rp ',
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: row.barcode,
                    decoration: InputDecoration(
                      labelText: 'Barcode (opsional)',
                      suffixIcon: IconButton(
                        tooltip: 'Scan barcode',
                        onPressed: () => _scanInto(row.barcode),
                        icon: const Icon(Icons.qr_code_scanner_rounded),
                      ),
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
