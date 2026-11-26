import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../telegram/data/telegram_service.dart';
import '../../telegram/presentation/telegram_settings_screen.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/recovery_code_view.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/data/recovery_code_service.dart';
import '../../products/data/product_models.dart';
import '../../backup/presentation/backup_screen.dart';
import '../../receipt/data/printer_settings.dart';
import '../../receipt/presentation/printer_settings_screen.dart';
import '../data/settings_repository.dart';
import 'change_pin_screen.dart';
import 'store_profile_screen.dart';
import 'users_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  void _open(BuildContext context, Widget screen) =>
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => screen));

  Future<void> _newRecoveryCode(BuildContext context, WidgetRef ref) async {
    final ok = await confirm(
      context,
      title: 'Buat kode pemulihan baru?',
      message: 'Kode pemulihan lama tidak akan berlaku lagi.',
      confirmLabel: 'Buat baru',
    );
    if (!ok || !context.mounted) return;
    final code = await ref.read(recoveryCodeServiceProvider).issueNew();
    if (!context.mounted) return;
    _open(
      context,
      Scaffold(
        appBar: AppBar(title: const Text('Kode Pemulihan')),
        body: Builder(
          builder: (context) => SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ContentWidth(
              child: RecoveryCodeView(
                code: code,
                doneLabel: 'Selesai',
                onDone: () => Navigator.pop(context),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickNearExpiry(BuildContext context, WidgetRef ref) async {
    final current =
        ref.read(nearExpiryDaysProvider).value ?? defaultNearExpiryDays;
    final picked = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Ingatkan berapa lama sebelum ED?'),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              'Berlaku untuk semua produk, kecuali produk yang diatur khusus.',
            ),
          ),
          RadioGroup<int>(
            groupValue: current,
            onChanged: (v) => Navigator.pop(context, v),
            child: Column(
              children: [
                for (final e in nearExpiryChoices.entries)
                  RadioListTile<int>(value: e.key, title: Text(e.value)),
              ],
            ),
          ),
        ],
      ),
    );
    if (picked == null) return;
    await ref
        .read(settingsRepositoryProvider)
        .set(SettingKeys.nearExpiryDays, '$picked');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOwner = ref.watch(isOwnerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan')),
      body: ListView(
        children: [
          if (isOwner) ...[
            const _Section('Apotek'),
            ListTile(
              leading: const Icon(Icons.local_pharmacy_outlined),
              title: const Text('Data apotek'),
              subtitle: const Text('Nama, alamat, telepon, catatan struk'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _open(context, const StoreProfileScreen()),
            ),
            ListTile(
              leading: const Icon(Icons.event_busy_outlined),
              title: const Text('Peringatan kedaluwarsa'),
              subtitle: Text(
                '${nearExpiryLabel(ref.watch(nearExpiryDaysProvider).value ?? defaultNearExpiryDays)} '
                'sebelum ED · bisa diatur khusus per produk',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _pickNearExpiry(context, ref),
            ),
            ListTile(
              leading: const Icon(Icons.group_outlined),
              title: const Text('Pengguna'),
              subtitle: const Text('Tambah kasir, atur ulang PIN'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _open(context, const UsersScreen()),
            ),
          ],
          if (isOwner) ...[
            ListTile(
              leading: const Icon(Icons.print_outlined),
              title: const Text('Printer & struk'),
              subtitle: Text(
                ref.watch(printerSettingsProvider).value?.description ?? '',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const PrinterSettingsScreen(),
                ),
              ),
            ),
          ],
          if (isOwner) ...[
            ListTile(
              leading: const Icon(Icons.send_outlined),
              title: const Text('Notifikasi Telegram'),
              subtitle: Text(switch (ref.watch(telegramStatusProvider).value) {
                TelegramStatus(enabled: false) => 'Belum ada bot · ketuk untuk menyiapkan',
                TelegramStatus(linked: true, :final chatName, :final pending) =>
                  pending == 0
                      ? 'Terhubung ke $chatName'
                      : 'Terhubung · $pending pesan menunggu',
                TelegramStatus() => 'Belum terhubung',
                null => '',
              }),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const TelegramSettingsScreen(),
                ),
              ),
            ),
          ],
          if (isOwner) ...[
            const _Section('Data'),
            ListTile(
              leading: const Icon(Icons.backup_outlined),
              title: const Text('Backup & pulihkan'),
              subtitle: const Text(
                'Simpan data ke Drive/WhatsApp, pulihkan dari backup',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const BackupScreen()),
              ),
            ),
          ],
          const _Section('Keamanan'),
          ListTile(
            leading: const Icon(Icons.pin_outlined),
            title: const Text('Ganti PIN saya'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(context, const ChangePinScreen()),
          ),
          if (isOwner)
            ListTile(
              leading: const Icon(Icons.key_outlined),
              title: const Text('Buat kode pemulihan baru'),
              subtitle: const Text('Jika kode lama hilang'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _newRecoveryCode(context, ref),
            ),
          if (isOwner) ...[
            const _Section('Segera hadir'),
            for (final (icon, label) in const [
              (Icons.qr_code_2_outlined, 'QRIS'),
              (Icons.upload_file_outlined, 'Impor produk dari Excel'),
            ])
              ListTile(enabled: false, leading: Icon(icon), title: Text(label)),
          ],
          const _Section('Tentang'),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('POS Apotek'),
            subtitle: Text('Versi 0.1.0'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
    child: Text(
      title,
      style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(color: Theme.of(context).colorScheme.primary),
    ),
  );
}
