import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/common.dart';
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
