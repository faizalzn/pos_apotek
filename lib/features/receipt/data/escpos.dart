import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'receipt_layout.dart';

/// Penyusun perintah ESC/POS — standar yang dipahami hampir semua printer
/// thermal (Epson, Xprinter, Zjiang, Panda, RPP02, dsb.). ADR-0005.
class EscPosBuilder {
  final _bytes = BytesBuilder();

  Uint8List get bytes => _bytes.toBytes();

  void init() => _bytes.add(const [0x1B, 0x40]);

  void align(ReceiptAlign a) => _bytes.add([0x1B, 0x61, a.index]);

  void bold(bool on) => _bytes.add([0x1B, 0x45, on ? 1 : 0]);

  /// Tinggi ganda (lebar tetap).
  void doubleHeight(bool on) => _bytes.add([0x1D, 0x21, on ? 0x01 : 0x00]);

  void text(String s) {
    _bytes.add(toPrintable(s).codeUnits);
    _bytes.addByte(0x0A);
  }

  void feed(int lines) => _bytes.add([0x1B, 0x64, lines.clamp(0, 255)]);

  /// Potong kertas (diabaikan oleh printer tanpa pemotong).
  void cut() => _bytes.add(const [0x1D, 0x56, 0x42, 0x00]);

  void line(ReceiptLine l) {
    align(l.align);
    if (l.bold) bold(true);
    if (l.large) doubleHeight(true);
    text(l.text);
    if (l.large) doubleHeight(false);
    if (l.bold) bold(false);
  }

  /// Gambar hitam-putih (GS v 0), dikirim per potongan 64 baris agar printer
  /// dengan buffer kecil tidak macet.
  void image(img.Image source, {required int maxWidth}) {
    var image = source;
    if (image.width > maxWidth) {
      image = img.copyResize(image, width: maxWidth);
    }
    final bits = monochrome(image);
    final widthBytes = (image.width + 7) ~/ 8;
    align(ReceiptAlign.center);
    const band = 64;
    for (var y0 = 0; y0 < image.height; y0 += band) {
      final h = (image.height - y0).clamp(0, band);
      _bytes.add([
        0x1D,
        0x76,
        0x30,
        0x00,
        widthBytes & 0xFF,
        widthBytes >> 8,
        h & 0xFF,
        h >> 8,
      ]);
      _bytes.add(bits.sublist(y0 * widthBytes, (y0 + h) * widthBytes));
    }
    align(ReceiptAlign.left);
  }
}

/// Mengubah gambar menjadi bit hitam (1) / putih (0), 8 piksel per byte.
/// Transparan dianggap putih; abu-abu diambangkan di 50%.
Uint8List monochrome(img.Image image) {
  final widthBytes = (image.width + 7) ~/ 8;
  final out = Uint8List(widthBytes * image.height);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final p = image.getPixel(x, y);
      final a = p.aNormalized;
      final lum =
          (0.299 * p.rNormalized +
          0.587 * p.gNormalized +
          0.114 * p.bNormalized);
      // Campur dengan putih sesuai transparansi.
      final value = lum * a + (1 - a);
      if (value < 0.5) {
        out[y * widthBytes + (x >> 3)] |= 0x80 >> (x & 7);
      }
    }
  }
  return out;
}

/// Struk lengkap dalam bentuk byte ESC/POS.
Uint8List receiptToEscPos(
  List<ReceiptLine> lines, {
  required PaperWidth paper,
  img.Image? logo,
}) {
  final b = EscPosBuilder()..init();
  if (logo != null) {
    b.image(logo, maxWidth: (paper.dots * 0.6).round());
    b.feed(1);
  }
  for (final l in lines) {
    b.line(l);
  }
  b
    ..feed(4)
    ..cut();
  return b.bytes;
}

/// Struk uji untuk memastikan printer tersambung & lebar kertas benar.
Uint8List testPage(PaperWidth paper, {img.Image? logo}) {
  final cols = paper.columns;
  return receiptToEscPos(
    [
      const ReceiptLine(
        'TES PRINTER',
        align: ReceiptAlign.center,
        bold: true,
        large: true,
      ),
      ReceiptLine('Kertas ${paper.label}', align: ReceiptAlign.center),
      ReceiptLine('-' * cols),
      ReceiptLine(
        '${'1234567890' * (cols ~/ 10)}${'1234567890'.substring(0, cols % 10)}',
      ),
      ReceiptLine('Baris di atas harus pas', align: ReceiptAlign.center),
      ReceiptLine('satu baris penuh.', align: ReceiptAlign.center),
      ReceiptLine('-' * cols),
      ReceiptLine(
        'Printer siap dipakai',
        align: ReceiptAlign.center,
        bold: true,
      ),
    ],
    paper: paper,
    logo: logo,
  );
}
