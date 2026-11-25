import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'dart:io';

import 'package:image_picker/image_picker.dart';

import '../../../core/widgets/common.dart';
import '../../products/data/photo_store.dart';
import '../../receipt/data/printer_settings.dart';
import '../data/settings_repository.dart';
import 'store_profile_fields.dart';

class StoreProfileScreen extends ConsumerStatefulWidget {
  const StoreProfileScreen({super.key});

  @override
  ConsumerState<StoreProfileScreen> createState() => _StoreProfileScreenState();
}

class _StoreProfileScreenState extends ConsumerState<StoreProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _controllers = StoreProfileControllers();
  bool _loaded = false;
  bool _saving = false;

  @override
  void dispose() {
    _controllers.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    await ref
        .read(settingsRepositoryProvider)
        .saveStoreProfile(_controllers.toProfile());
    if (!mounted) return;
    setState(() => _saving = false);
    showMessage(context, 'Data apotek tersimpan');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(storeProfileProvider);
    if (!_loaded && profile.hasValue) {
      _controllers.load(profile.requireValue);
      _loaded = true;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Data Apotek')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ContentWidth(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const StoreLogoPicker(),
                        const SizedBox(height: 16),
                        StoreProfileFields(
                          controllers: _controllers,
                          showReceiptFooter: true,
                        ),
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: _saving ? null : _save,
                          child: const Text('Simpan'),
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

/// Logo apotek (opsional) untuk struk. Disimpan di folder foto agar ikut
/// ter-backup.
class StoreLogoPicker extends ConsumerStatefulWidget {
  const StoreLogoPicker({super.key});

  @override
  ConsumerState<StoreLogoPicker> createState() => _StoreLogoPickerState();
}

class _StoreLogoPickerState extends ConsumerState<StoreLogoPicker> {
  bool _busy = false;

  Future<void> _pick(String? current) async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
    );
    if (picked == null) return;
    setState(() => _busy = true);
    try {
      final store = await ref.read(photoStoreProvider.future);
      final name = await store.save(picked.path);
      await ref
          .read(settingsRepositoryProvider)
          .set(PrinterKeys.logoFile, name);
      await store.delete(current);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(String current) async {
    await ref.read(settingsRepositoryProvider).set(PrinterKeys.logoFile, '');
    await (await ref.read(photoStoreProvider.future)).delete(current);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final logo = ref.watch(printerSettingsProvider).value?.logoFile;
    final store = ref.watch(photoStoreProvider).value;
    final File? file = logo == null || store == null
        ? null
        : store.fileOf(logo);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              clipBehavior: Clip.antiAlias,
              child: file == null
                  ? Icon(Icons.image_outlined, color: theme.colorScheme.outline)
                  : Image.file(file, fit: BoxFit.contain),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Logo apotek (opsional)',
                    style: theme.textTheme.titleSmall,
                  ),
                  Text(
                    'Tampil di struk. Logo hitam-putih sederhana paling jelas '
                    'di printer thermal.',
                    style: theme.textTheme.bodySmall,
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: _busy ? null : () => _pick(logo),
                        child: Text(logo == null ? 'Pilih logo' : 'Ganti'),
                      ),
                      if (logo != null)
                        TextButton(
                          onPressed: _busy ? null : () => _remove(logo),
                          child: const Text('Hapus'),
                        ),
                    ],
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
