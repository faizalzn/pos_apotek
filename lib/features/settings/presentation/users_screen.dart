import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/database/app_database.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/pin_pad.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/data/user_repository.dart';

/// Daftar pengguna (khusus Pemilik).
class UsersScreen extends ConsumerWidget {
  const UsersScreen({super.key});

  Future<void> _actions(
    BuildContext context,
    WidgetRef ref,
    AppUser user,
  ) async {
    final me = ref.read(sessionProvider);
    final isMe = me?.id == user.id;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                user.name,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              subtitle: Text(user.role.label),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Ubah nama'),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
            if (!isMe)
              ListTile(
                leading: const Icon(Icons.pin_outlined),
                title: const Text('Atur ulang PIN'),
                onTap: () => Navigator.pop(context, 'pin'),
              ),
            if (!isMe)
              ListTile(
                leading: Icon(
                  user.isActive
                      ? Icons.person_off_outlined
                      : Icons.person_outline,
                ),
                title: Text(user.isActive ? 'Nonaktifkan' : 'Aktifkan kembali'),
                onTap: () => Navigator.pop(context, 'toggle'),
              ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    final repo = ref.read(userRepositoryProvider);

    try {
      switch (action) {
        case 'rename':
          final name = await _askName(context, user.name);
          if (name == null) return;
          await repo.rename(user.id, name);
          final updated = await repo.byId(user.id);
          if (updated != null) {
            ref.read(sessionProvider.notifier).refresh(updated);
          }
          if (context.mounted) showMessage(context, 'Nama diubah');
        case 'pin':
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => _SetUserPinScreen(user: user),
            ),
          );
        case 'toggle':
          if (user.isActive) {
            final ok = await confirm(
              context,
              title: 'Nonaktifkan ${user.name}?',
              message:
                  'Pengguna ini tidak bisa masuk lagi sampai diaktifkan kembali. '
                  'Riwayat transaksinya tetap tersimpan.',
              confirmLabel: 'Nonaktifkan',
              destructive: true,
            );
            if (!ok) return;
          }
          await repo.setActive(user.id, active: !user.isActive);
      }
    } on UserRuleException catch (e) {
      if (context.mounted) showMessage(context, e.message, error: true);
    }
  }

  Future<String?> _askName(BuildContext context, String current) {
    final controller = TextEditingController(text: current);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ubah nama'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Nama'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Simpan'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(allUsersProvider);
    final me = ref.watch(sessionProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Pengguna')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const _AddUserScreen()),
        ),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Tambah pengguna'),
      ),
      body: users.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Gagal memuat: $e')),
        data: (list) => ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            for (final user in list)
              ListTile(
                onTap: () => _actions(context, ref, user),
                leading: CircleAvatar(
                  backgroundColor: user.isActive
                      ? null
                      : theme.colorScheme.surfaceContainerHighest,
                  child: Text(initials(user.name)),
                ),
                title: Text(
                  user.id == me?.id ? '${user.name} (Anda)' : user.name,
                  style: user.isActive
                      ? null
                      : TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
                subtitle: Text(
                  user.isActive ? user.role.label : '${user.role.label} · Nonaktif',
                ),
                trailing: const Icon(Icons.more_vert),
              ),
          ],
        ),
      ),
    );
  }
}

class _AddUserScreen extends ConsumerStatefulWidget {
  const _AddUserScreen();

  @override
  ConsumerState<_AddUserScreen> createState() => _AddUserScreenState();
}

class _AddUserScreenState extends ConsumerState<_AddUserScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  UserRole _role = UserRole.cashier;
  bool _choosingPin = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create(String pin) async {
    try {
      await ref
          .read(userRepositoryProvider)
          .create(name: _name.text, role: _role, pin: pin);
    } on UserRuleException catch (e) {
      // Nama ganda, dsb. → kembali ke isian nama.
      if (!mounted) return;
      setState(() => _choosingPin = false);
      showMessage(context, e.message, error: true);
      return;
    }
    if (!mounted) return;
    showMessage(context, '${_name.text.trim()} ditambahkan');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tambah Pengguna')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ContentWidth(
            child: _choosingPin
                ? PinSetupFlow(
                    title: 'Buat PIN untuk ${_name.text.trim()}',
                    subtitle: 'Beri tahu PIN ini kepada yang bersangkutan',
                    onPinChosen: _create,
                  )
                : Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _name,
                          autofocus: true,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Nama *',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Nama wajib diisi'
                              : null,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Peran',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        SegmentedButton<UserRole>(
                          segments: const [
                            ButtonSegment(
                              value: UserRole.cashier,
                              label: Text('Kasir'),
                              icon: Icon(Icons.point_of_sale_outlined),
                            ),
                            ButtonSegment(
                              value: UserRole.owner,
                              label: Text('Pemilik'),
                              icon: Icon(Icons.verified_user_outlined),
                            ),
                          ],
                          selected: {_role},
                          onSelectionChanged: (s) =>
                              setState(() => _role = s.first),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _role == UserRole.cashier
                              ? 'Kasir hanya bisa berjualan dan melihat stok.'
                              : 'Pemilik punya akses penuh, termasuk laba dan pengguna.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: () {
                            if (_formKey.currentState!.validate()) {
                              setState(() => _choosingPin = true);
                            }
                          },
                          child: const Text('Lanjut ke PIN'),
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

class _SetUserPinScreen extends ConsumerWidget {
  const _SetUserPinScreen({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Atur Ulang PIN')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: PinSetupFlow(
              title: 'PIN baru untuk ${user.name}',
              subtitle: 'Beri tahu PIN ini kepada yang bersangkutan',
              onPinChosen: (pin) async {
                await ref.read(userRepositoryProvider).setPin(user.id, pin);
                if (!context.mounted) return;
                showMessage(context, 'PIN ${user.name} diperbarui');
                Navigator.pop(context);
              },
            ),
          ),
        ),
      ),
    );
  }
}
