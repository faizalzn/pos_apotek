import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/widgets/common.dart';
import '../../auth/application/session_controller.dart';
import '../data/printer_service.dart';
import '../data/printer_settings.dart';
import '../data/receipt_service.dart';
import 'printer_settings_screen.dart';

/// Nomor HP Indonesia → format wa.me (62…). `null` bila tidak valid.
String? normalizeWhatsAppNumber(String input) {
  var digits = input.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return null;
  if (digits.startsWith('0')) {
    digits = '62${digits.substring(1)}';
  } else if (digits.startsWith('8')) {
    digits = '62$digits';
  }
  return digits.length >= 10 && digits.length <= 15 ? digits : null;
}

/// Status cetak untuk ditampilkan di layar.
enum PrintStatus { idle, printing, done, failed }

/// Tombol Cetak / WhatsApp / Bagikan untuk satu transaksi.
class ReceiptActions extends ConsumerStatefulWidget {
  const ReceiptActions({
    super.key,
    required this.saleId,
    this.isCopy = false,
    this.autoPrint = false,
  });

  final String saleId;

  /// Cetak ulang dari riwayat → struk diberi tanda SALINAN.
  final bool isCopy;

  /// Cetak otomatis sekali saat tampil (bila diaktifkan di pengaturan).
  final bool autoPrint;

  @override
  ConsumerState<ReceiptActions> createState() => _ReceiptActionsState();
}

class _ReceiptActionsState extends ConsumerState<ReceiptActions> {
  PrintStatus _status = PrintStatus.idle;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoPrint) _autoPrint();
  }

  Future<void> _autoPrint() async {
    final s = await ref.read(receiptServiceProvider).settings();
    // Layanan cetak Android membuka dialog — tidak cocok untuk otomatis.
    if (mounted && s.autoPrint && s.isReady && s.isThermal) await _print(s);
  }

  Future<void> _print([PrinterSettings? known]) async {
    final service = ref.read(receiptServiceProvider);
    final s = known ?? await service.settings();
    if (!mounted) return;
    if (!s.isReady) {
      await _askToConfigure();
      return;
    }
    setState(() {
      _status = PrintStatus.printing;
      _error = null;
    });
    try {
      if (s.type == PrinterType.android) {
        final bytes = await service.pdf(widget.saleId, copy: widget.isCopy);
        await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'Struk');
      } else {
        await service.printThermal(widget.saleId, copy: widget.isCopy);
      }
      if (mounted) setState(() => _status = PrintStatus.done);
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _status = PrintStatus.failed;
          _error = e is PrinterException ? e.message : 'Gagal mencetak: $e';
        });
      }
    }
  }

  Future<void> _askToConfigure() async {
    final isOwner = ref.read(isOwnerProvider);
    if (!isOwner) {
      showMessage(
        context,
        'Printer belum diatur. Minta Pemilik mengaturnya di Pengaturan.',
      );
      return;
    }
    final ok = await confirm(
      context,
      title: 'Printer belum diatur',
      message:
          'Atur printer sekarang? Struk tetap bisa dikirim lewat WhatsApp '
          'atau dibagikan sebagai PDF tanpa printer.',
      confirmLabel: 'Atur printer',
    );
    if (ok && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const PrinterSettingsScreen()),
      );
    }
  }

  Future<void> _whatsApp() async {
    final number = await _askNumber();
    if (number == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final text = await ref.read(receiptServiceProvider).text(widget.saleId);
      final uri = Uri.https('wa.me', number.isEmpty ? '/' : '/$number', {
        'text': text,
      });
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        showMessage(context, 'WhatsApp tidak bisa dibuka', error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// '' = pilih kontak di WhatsApp; null = batal.
  Future<String?> _askNumber() {
    final controller = TextEditingController();
    String? error;
    return showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          void submit() {
            final text = controller.text.trim();
            if (text.isEmpty) {
              Navigator.pop(context, '');
              return;
            }
            final n = normalizeWhatsAppNumber(text);
            if (n == null) {
              setState(() => error = 'Nomor tidak valid');
            } else {
              Navigator.pop(context, n);
            }
          }

          return AlertDialog(
            title: const Text('Kirim struk via WhatsApp'),
            content: TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9+ -]')),
              ],
              onSubmitted: (_) => submit(),
              decoration: InputDecoration(
                labelText: 'Nomor WhatsApp pelanggan',
                hintText: '08xx xxxx xxxx',
                helperText: 'Kosongkan untuk memilih kontak di WhatsApp',
                errorText: error,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: submit,
                child: const Text('Buka WhatsApp'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _share({required bool asImage}) async {
    setState(() => _busy = true);
    try {
      final service = ref.read(receiptServiceProvider);
      final pdf = await service.pdf(widget.saleId, copy: widget.isCopy);
      final number = (await service.load(widget.saleId)).sale.number;
      final dir = await getTemporaryDirectory();
      final File file;
      if (asImage) {
        final page = await Printing.raster(pdf, dpi: 200).first;
        file = File('${dir.path}/struk_$number.png');
        await file.writeAsBytes(await page.toPng());
      } else {
        file = File('${dir.path}/struk_$number.pdf');
        await file.writeAsBytes(pdf);
      }
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile(
              file.path,
              mimeType: asImage ? 'image/png' : 'application/pdf',
            ),
          ],
          subject: 'Struk $number',
        ),
      );
    } on Object catch (e) {
      if (mounted) showMessage(context, 'Gagal membuat struk: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(printerSettingsProvider).value;
    final printing = _status == PrintStatus.printing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_status != PrintStatus.idle)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                switch (_status) {
                  PrintStatus.printing => const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  PrintStatus.done => Icon(
                    Icons.check_circle,
                    color: theme.colorScheme.primary,
                  ),
                  _ => Icon(
                    Icons.error_outline,
                    color: theme.colorScheme.error,
                  ),
                },
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    switch (_status) {
                      PrintStatus.printing => 'Mencetak struk…',
                      PrintStatus.done => 'Struk terkirim ke printer',
                      _ => _error ?? 'Gagal mencetak',
                    },
                    key: const Key('print-status'),
                    style: TextStyle(
                      color: _status == PrintStatus.failed
                          ? theme.colorScheme.error
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        FilledButton.tonalIcon(
          key: const Key('print-receipt'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: printing ? null : () => _print(),
          icon: const Icon(Icons.print_outlined),
          label: Text(
            _status == PrintStatus.failed
                ? 'Coba cetak lagi'
                : (widget.isCopy ? 'Cetak ulang struk' : 'Cetak struk'),
          ),
        ),
        if (settings != null && !settings.isReady)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Printer belum diatur',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('receipt-whatsapp'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: _busy ? null : _whatsApp,
                icon: const Icon(Icons.chat_outlined),
                label: const Text('WhatsApp'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: MenuAnchor(
                builder: (context, controller, _) => OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: _busy
                      ? null
                      : () => controller.isOpen
                            ? controller.close()
                            : controller.open(),
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('Bagikan'),
                ),
                menuChildren: [
                  MenuItemButton(
                    leadingIcon: const Icon(Icons.image_outlined),
                    onPressed: () => _share(asImage: true),
                    child: const Text('Sebagai gambar'),
                  ),
                  MenuItemButton(
                    leadingIcon: const Icon(Icons.picture_as_pdf_outlined),
                    onPressed: () => _share(asImage: false),
                    child: const Text('Sebagai PDF'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
