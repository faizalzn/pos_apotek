import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/database/app_database.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/pin_pad.dart';
import '../../settings/data/settings_repository.dart';
import '../application/session_controller.dart';
import '../data/user_repository.dart';
import 'forgot_pin_screen.dart';

/// Layar masuk: pilih nama, lalu ketik PIN.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  String? _selectedId;
  String? _error;

  Future<void> _checkPin(AppUser user, String pin) async {
    final result = await ref.read(userRepositoryProvider).checkPin(user.id, pin);
    if (!mounted) return;
    switch (result) {
      case PinAccepted(:final user):
        ref.read(sessionProvider.notifier).signIn(user);
      case PinRejected(:final attemptsLeft):
        setState(() => _error = 'PIN salah. Sisa percobaan: $attemptsLeft');
      case PinLocked(:final remaining):
        setState(
          () => _error =
              'Terlalu banyak salah. Coba lagi dalam ${formatWait(remaining)}.',
        );
    }
  }

  void _select(String? id) => setState(() {
        _selectedId = id;
        _error = null;
      });

  Future<void> _forgotPin(AppUser user) async {
    if (user.role == UserRole.cashier) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Lupa PIN?'),
          content: const Text(
            'Minta Pemilik untuk mengatur ulang PIN Anda di menu '
            'Pengaturan → Pengguna.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Mengerti'),
            ),
          ],
        ),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ForgotPinScreen(owner: user)),
    );
    if (mounted) setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final storeName = ref.watch(storeProfileProvider).value?.name ?? '';
    final users = ref.watch(activeUsersProvider);

    return Scaffold(
      body: SafeArea(
        child: users.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Gagal memuat pengguna: $e')),
          data: (list) {
            final only = list.length == 1 ? list.first : null;
            final selected = list
                    .where((u) => u.id == _selectedId)
                    .firstOrNull ??
                only;

            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ContentWidth(
                maxWidth: 440,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 16),
                    Icon(
                      Icons.local_pharmacy_rounded,
                      size: 44,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      storeName,
                      style: theme.textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    if (selected == null)
                      _UserPicker(users: list, onSelected: (u) => _select(u.id))
                    else ...[
                      PinPad(
                        key: ValueKey(selected.id),
                        title: 'Halo, ${selected.name}',
                        subtitle: 'Masukkan PIN Anda',
                        errorText: _error,
                        onCompleted: (pin) => _checkPin(selected, pin),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        children: [
                          if (only == null)
                            TextButton.icon(
                              onPressed: () => _select(null),
                              icon: const Icon(Icons.swap_horiz),
                              label: const Text('Ganti pengguna'),
                            ),
                          TextButton(
                            onPressed: () => _forgotPin(selected),
                            child: const Text('Lupa PIN?'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _UserPicker extends StatelessWidget {
  const _UserPicker({required this.users, required this.onSelected});

  final List<AppUser> users;
  final ValueChanged<AppUser> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Siapa yang bertugas?',
          style: theme.textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        for (final user in users)
          Card(
            child: ListTile(
              onTap: () => onSelected(user),
              leading: CircleAvatar(child: Text(initials(user.name))),
              title: Text(user.name, style: theme.textTheme.titleMedium),
              subtitle: Text(user.role.label),
              trailing: const Icon(Icons.chevron_right),
            ),
          ),
      ],
    );
  }
}
