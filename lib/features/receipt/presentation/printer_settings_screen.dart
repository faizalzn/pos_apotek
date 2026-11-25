import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:printing/printing.dart';

import '../../../core/widgets/common.dart';
import '../../settings/data/settings_repository.dart';
import '../data/printer_service.dart';
import '../data/printer_settings.dart';
import '../data/whatsapp_launcher.dart';
import '../data/receipt_layout.dart';
import '../data/receipt_service.dart';

/// Pengaturan printer & struk (khusus Pemilik).
class PrinterSettingsScreen extends ConsumerStatefulWidget {
  const PrinterSettingsScreen({super.key});

  @override
  ConsumerState<PrinterSettingsScreen> createState() =>
      _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends ConsumerState<PrinterSettingsScreen> {
  PrinterSettings? _s;
  final _host = TextEditingController();
  final _port = TextEditingController();
  bool _testing = false;

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  Future<void> _save(PrinterSettings s) async {
    setState(() => _s = s);
    await ref.read(settingsRepositoryProvider).setAll(s.toMap());
  }

  PrinterSettings _withNetworkFields(PrinterSettings s) => s.copyWith(
    host: _host.text.trim(),
    port: int.tryParse(_port.text) ?? 9100,
  );

  Future<void> _pickBluetooth() async {
    final List<PairedPrinter> devices;
    try {
      devices = await ref.read(printerServiceProvider).pairedDevices();
    } on PrinterException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
      return;
    }
    if (!mounted) return;
    final picked = await showModalBottomSheet<PairedPrinter>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text('Pilih printer'),
              subtitle: Text(
                'Printer belum ada di daftar? Nyalakan printer, lalu pasangkan '
                '(pair) dulu di Pengaturan Bluetooth HP. PIN biasanya 0000 atau 1234.',
              ),
            ),
            if (devices.isEmpty)
              const ListTile(
                title: Text('Belum ada perangkat Bluetooth yang dipasangkan'),
              ),
            for (final d in devices)
              ListTile(
                leading: const Icon(Icons.print_outlined),
                title: Text(d.name.isEmpty ? '(tanpa nama)' : d.name),
                subtitle: Text(d.address),
                onTap: () => Navigator.pop(context, d),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null) {
      await _save(_s!.copyWith(btAddress: picked.address, btName: picked.name));
    }
  }

  Future<void> _test() async {
    var s = _s!;
    if (s.type == PrinterType.network) {
      s = _withNetworkFields(s);
      await _save(s);
    }
    if (!mounted) return;
    if (!s.isReady) {
      showMessage(context, 'Lengkapi pengaturan printer dulu', error: true);
      return;
    }
    setState(() => _testing = true);
    try {
      if (s.type == PrinterType.android) {
        final cols = s.paper.columns;
        final bytes = await receiptPdf([
          const ReceiptLine(
            'TES PRINTER',
            align: ReceiptAlign.center,
            bold: true,
            large: true,
          ),
          ReceiptLine('-' * cols),
          const ReceiptLine('Printer siap dipakai', align: ReceiptAlign.center),
        ], paper: s.paper);
        await Printing.layoutPdf(
          onLayout: (_) async => bytes,
          name: 'Tes printer',
        );
      } else {
        await ref.read(receiptServiceProvider).printTest(s);
        if (mounted) {
          showMessage(context, 'Tes terkirim. Periksa hasil cetakan.');
        }
      }
    } on Object catch (e) {
      if (mounted) {
        showMessage(
          context,
          e is PrinterException ? e.message : 'Gagal: $e',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(printerSettingsProvider);
    if (_s == null && async.hasValue) {
      _s = async.requireValue;
      _host.text = _s!.host;
      _port.text = '${_s!.port}';
    }
    final s = _s;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Printer & Struk')),
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                ContentWidth(
                  maxWidth: 600,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _header(context, 'Jenis printer'),
                      RadioGroup<PrinterType>(
                        groupValue: s.type,
                        onChanged: (t) {
                          if (t != null) {
                            _save(_withNetworkFields(s).copyWith(type: t));
                          }
                        },
                        child: Column(
                          children: [
                            for (final t in PrinterType.values)
                              RadioListTile<PrinterType>(
                                value: t,
                                title: Text(t.label),
                                subtitle: switch (t) {
                                  PrinterType.none => const Text(
                                    'Struk tetap bisa dikirim via WhatsApp / PDF',
                                  ),
                                  PrinterType.bluetooth => const Text(
                                    'Paling umum: printer kecil 58 mm / 80 mm',
                                  ),
                                  PrinterType.network => const Text(
                                    'Printer kasir yang tersambung ke WiFi toko',
                                  ),
                                  PrinterType.android => const Text(
                                    'Printer biasa (Epson, Canon, HP) yang punya '
                                    'plugin cetak di HP',
                                  ),
                                },
                              ),
                          ],
                        ),
                      ),
                      if (s.type == PrinterType.bluetooth)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Card(
                            child: ListTile(
                              leading: const Icon(Icons.bluetooth),
                              title: Text(
                                s.btAddress.isEmpty
                                    ? 'Pilih printer'
                                    : s.btName,
                              ),
                              subtitle: Text(
                                s.btAddress.isEmpty
                                    ? 'Belum dipilih'
                                    : s.btAddress,
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: _pickBluetooth,
                            ),
                          ),
                        ),
                      if (s.type == PrinterType.network)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: TextField(
                                  controller: _host,
                                  keyboardType: TextInputType.url,
                                  decoration: const InputDecoration(
                                    labelText: 'Alamat IP printer',
                                    hintText: '192.168.1.100',
                                  ),
                                  onChanged: (_) =>
                                      _save(_withNetworkFields(s)),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextField(
                                  controller: _port,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  decoration: const InputDecoration(
                                    labelText: 'Port',
                                  ),
                                  onChanged: (_) =>
                                      _save(_withNetworkFields(s)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (s.type != PrinterType.none) ...[
                        _header(context, 'Lebar kertas'),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: SegmentedButton<PaperWidth>(
                            segments: [
                              for (final p in PaperWidth.values)
                                ButtonSegment(value: p, label: Text(p.label)),
                            ],
                            selected: {s.paper},
                            onSelectionChanged: (v) =>
                                _save(s.copyWith(paper: v.first)),
                          ),
                        ),
                        if (s.isThermal)
                          SwitchListTile(
                            title: const Text(
                              'Cetak otomatis setelah transaksi',
                            ),
                            value: s.autoPrint,
                            onChanged: (v) => _save(s.copyWith(autoPrint: v)),
                          ),
                        SwitchListTile(
                          title: const Text('Tampilkan logo di struk'),
                          subtitle: Text(
                            s.logoFile == null
                                ? 'Logo belum diatur (Pengaturan → Data apotek)'
                                : 'Logo dari Data apotek',
                          ),
                          value: s.showLogo,
                          onChanged: (v) => _save(s.copyWith(showLogo: v)),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                            ),
                            onPressed: _testing ? null : _test,
                            icon: _testing
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.print_outlined),
                            label: const Text('Cetak tes'),
                          ),
                        ),
                      ],
                      _header(context, 'WhatsApp'),
                      const WhatsAppChoiceTile(),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'Belum punya printer? Pilihan yang cocok untuk apotek kecil: '
                          'printer thermal Bluetooth 58 mm yang mendukung ESC/POS '
                          '(hampir semua merek, mis. Xprinter, Zjiang, Panda, EPPOS, '
                          'RPP02). Hindari printer yang hanya bisa dipakai dengan '
                          'aplikasi bawaannya sendiri.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _header(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}

/// Pilihan WhatsApp untuk mengirim struk (bila WhatsApp & WA Business terpasang).
class WhatsAppChoiceTile extends ConsumerStatefulWidget {
  const WhatsAppChoiceTile({super.key});

  @override
  ConsumerState<WhatsAppChoiceTile> createState() => _WhatsAppChoiceTileState();
}

class _WhatsAppChoiceTileState extends ConsumerState<WhatsAppChoiceTile> {
  WhatsAppApp? _choice;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    ref.read(whatsAppLauncherProvider).preference().then((v) {
      if (mounted) {
        setState(() {
          _choice = v;
          _loaded = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DropdownButtonFormField<WhatsAppApp?>(
        initialValue: _choice,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Kirim struk lewat',
          helperText: 'Berlaku bila WhatsApp dan WhatsApp Business sama-sama terpasang',
          helperMaxLines: 2,
        ),
        items: [
          const DropdownMenuItem(value: null, child: Text('Tanya setiap kali')),
          for (final a in WhatsAppApp.values)
            DropdownMenuItem(value: a, child: Text(a.label)),
        ],
        onChanged: (v) {
          setState(() => _choice = v);
          ref.read(whatsAppLauncherProvider).setPreference(v);
        },
      ),
    );
  }
}
