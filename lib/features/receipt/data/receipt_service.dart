import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../products/data/photo_store.dart';
import '../../sales/data/sale_service.dart';
import '../../settings/data/settings_repository.dart';
import 'escpos.dart';
import 'printer_service.dart';
import 'printer_settings.dart';
import 'receipt_layout.dart';

/// Menyusun struk dari transaksi lalu mencetak / membuat PDF / teks.
class ReceiptService {
  ReceiptService(this._sales, this._settings, this._photos, this._printer);

  final SaleService _sales;
  final SettingsRepository _settings;
  final Future<PhotoStore> _photos;
  final PrinterService _printer;

  Future<PrinterSettings> settings() async =>
      PrinterSettings.fromMap(await _settings.getAll());

  Future<ReceiptData> load(String saleId, {bool copy = false}) async {
    final detail = await _sales.getDetail(saleId);
    if (detail == null) {
      throw const PrinterException('Transaksi tidak ditemukan');
    }
    final store = StoreProfile.fromMap(await _settings.getAll());
    return ReceiptData(
      store: store,
      sale: detail.sale,
      items: detail.items,
      cashierName: detail.cashierName,
      isCopy: copy,
    );
  }

  Future<File?> _logoFile(PrinterSettings s) async {
    if (!s.showLogo || s.logoFile == null) return null;
    final file = (await _photos).fileOf(s.logoFile!);
    return await file.exists() ? file : null;
  }

  Future<img.Image?> _logoImage(PrinterSettings s) async {
    final file = await _logoFile(s);
    if (file == null) return null;
    return img.decodeImage(await file.readAsBytes());
  }

  /// Cetak ke printer thermal sesuai pengaturan.
  Future<void> printThermal(String saleId, {bool copy = false}) async {
    final s = await settings();
    final lines = buildReceipt(await load(saleId, copy: copy), s.paper.columns);
    final bytes = receiptToEscPos(
      lines,
      paper: s.paper,
      logo: await _logoImage(s),
    );
    await _printer.send(s, bytes);
  }

  Future<void> printTest(PrinterSettings s) async =>
      _printer.send(s, testPage(s.paper, logo: await _logoImage(s)));

  Future<Uint8List> pdf(String saleId, {bool copy = false}) async {
    final s = await settings();
    final lines = buildReceipt(await load(saleId, copy: copy), s.paper.columns);
    final logo = await _logoFile(s);
    return receiptPdf(
      lines,
      paper: s.paper,
      logo: logo == null ? null : await logo.readAsBytes(),
    );
  }

  Future<String> text(String saleId) async {
    // Teks WhatsApp selalu 32 kolom agar rapi di layar HP.
    const columns = 32;
    return receiptAsText(buildReceipt(await load(saleId), columns), columns);
  }
}

/// PDF selebar kertas struk; huruf monospace agar sama persis dengan cetakan.
Future<Uint8List> receiptPdf(
  List<ReceiptLine> lines, {
  required PaperWidth paper,
  Uint8List? logo,
}) async {
  const margin = 3 * PdfPageFormat.mm;
  final width = paper.millimeters * PdfPageFormat.mm;
  final inner = width - 2 * margin;
  // Lebar huruf Courier = 0,6 × ukurannya.
  final size = inner / (paper.columns * 0.6);
  final regular = pw.Font.courier();
  final bold = pw.Font.courierBold();

  pw.TextAlign alignOf(ReceiptAlign a) => switch (a) {
    ReceiptAlign.left => pw.TextAlign.left,
    ReceiptAlign.center => pw.TextAlign.center,
    ReceiptAlign.right => pw.TextAlign.right,
  };

  final doc = pw.Document(title: 'Struk', creator: 'POS Apotek');
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat(width, double.infinity, marginAll: margin),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          if (logo != null)
            pw.Center(
              child: pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 4),
                child: pw.Image(pw.MemoryImage(logo), width: inner * 0.6),
              ),
            ),
          for (final l in lines)
            pw.Text(
              l.text,
              textAlign: alignOf(l.align),
              style: pw.TextStyle(
                font: l.bold ? bold : regular,
                // Baris besar diperbesar selama masih muat satu baris.
                fontSize: l.large && l.text.isNotEmpty
                    ? size * (paper.columns / l.text.length).clamp(1.0, 1.4)
                    : size,
              ),
            ),
        ],
      ),
    ),
  );
  return doc.save();
}

final receiptServiceProvider = Provider<ReceiptService>(
  (ref) => ReceiptService(
    ref.watch(saleServiceProvider),
    ref.watch(settingsRepositoryProvider),
    ref.watch(photoStoreProvider.future),
    ref.watch(printerServiceProvider),
  ),
);
