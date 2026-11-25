import '../../../core/database/app_database.dart';
import '../../../core/format.dart';
import '../../settings/data/settings_repository.dart';

/// Lebar kertas printer thermal.
enum PaperWidth {
  mm58(58, 32, 384),
  mm80(80, 48, 576);

  const PaperWidth(this.millimeters, this.columns, this.dots);

  final int millimeters;

  /// Jumlah karakter per baris (font standar printer).
  final int columns;

  /// Lebar area cetak dalam titik (203 dpi).
  final int dots;

  String get label => '$millimeters mm';

  static PaperWidth fromName(String? name) =>
      values.firstWhere((p) => p.name == name, orElse: () => mm58);
}

enum ReceiptAlign { left, center, right }

/// Satu baris struk. Dipakai bersama oleh printer thermal, PDF, dan teks.
class ReceiptLine {
  const ReceiptLine(
    this.text, {
    this.align = ReceiptAlign.left,
    this.bold = false,
    this.large = false,
  });

  final String text;
  final ReceiptAlign align;
  final bool bold;

  /// Tinggi ganda di printer thermal (lebar tetap, jadi kolom tidak bergeser).
  final bool large;
}

/// Data yang dibutuhkan untuk menyusun struk.
class ReceiptData {
  const ReceiptData({
    required this.store,
    required this.sale,
    required this.items,
    required this.cashierName,
    this.isCopy = false,
  });

  final StoreProfile store;
  final Sale sale;
  final List<SaleItem> items;
  final String cashierName;

  /// Cetak ulang → diberi tanda "SALINAN".
  final bool isCopy;
}

/// Menyusun baris-baris struk untuk lebar [columns] karakter.
List<ReceiptLine> buildReceipt(ReceiptData data, int columns) {
  final s = data.sale;
  final lines = <ReceiptLine>[];
  final divider = ReceiptLine('-' * columns);

  void center(String text, {bool bold = false, bool large = false}) {
    for (final part in wrapText(text, columns)) {
      lines.add(
        ReceiptLine(part, align: ReceiptAlign.center, bold: bold, large: large),
      );
    }
  }

  void pair(
    String left,
    String right, {
    bool bold = false,
    bool large = false,
  }) {
    for (final l in twoColumns(left, right, columns)) {
      lines.add(ReceiptLine(l, bold: bold, large: large));
    }
  }

  // Kepala
  center(data.store.name.toUpperCase(), bold: true, large: true);
  if (data.store.address.isNotEmpty) center(data.store.address);
  if (data.store.phone.isNotEmpty) center('Telp ${data.store.phone}');
  lines.add(divider);
  pair('No', s.number);
  pair('Tanggal', _dateTime(s.createdAt));
  pair('Kasir', data.cashierName);
  if (data.isCopy) center('*** SALINAN ***', bold: true);
  if (s.status == SaleStatus.voided) {
    center('*** TRANSAKSI DIBATALKAN ***', bold: true);
  }
  lines.add(divider);

  // Barang
  for (final item in data.items) {
    for (final part in wrapText(item.productName, columns)) {
      lines.add(ReceiptLine(part));
    }
    pair(
      '  ${item.quantity} ${item.unitName} x ${formatNumber(item.unitPrice)}',
      formatNumber(item.unitPrice * item.quantity),
    );
    if (item.discount > 0) pair('  Diskon', '-${formatNumber(item.discount)}');
  }
  lines.add(divider);

  // Ringkasan
  if (s.itemDiscount > 0 || s.discount > 0) {
    pair('Subtotal', formatNumber(s.subtotal));
    if (s.itemDiscount > 0) {
      pair('Diskon barang', '-${formatNumber(s.itemDiscount)}');
    }
    if (s.discount > 0) pair('Diskon', '-${formatNumber(s.discount)}');
  }
  pair('TOTAL', formatRupiah(s.total), bold: true, large: true);
  if (s.paymentMethod == PaymentMethod.cash) {
    pair('Tunai', formatNumber(s.amountPaid));
    pair('Kembali', formatNumber(s.change));
  } else {
    pair('QRIS', formatNumber(s.amountPaid));
  }
  lines.add(divider);

  if (data.store.receiptFooter.isNotEmpty) center(data.store.receiptFooter);
  return [
    for (final l in lines)
      ReceiptLine(
        toPrintable(l.text),
        align: l.align,
        bold: l.bold,
        large: l.large,
      ),
  ];
}

/// Struk sebagai teks biasa (untuk WhatsApp), dalam blok monospace.
String receiptAsText(List<ReceiptLine> lines, int columns) {
  final out = StringBuffer('```\n');
  for (final l in lines) {
    out.writeln(
      switch (l.align) {
        ReceiptAlign.left => l.text,
        ReceiptAlign.center => _padCenter(l.text, columns),
        ReceiptAlign.right => l.text.padLeft(columns),
      }.trimRight(),
    );
  }
  out.write('```');
  return out.toString();
}

String _padCenter(String text, int columns) {
  if (text.length >= columns) return text;
  return ' ' * ((columns - text.length) ~/ 2) + text;
}

/// Teks kiri & kanan dalam satu baris; bila tidak muat, kiri di baris
/// sendiri dan kanan rata kanan di baris berikutnya.
List<String> twoColumns(String left, String right, int columns) {
  if (left.length + right.length + 1 <= columns) {
    return [left + ' ' * (columns - left.length - right.length) + right];
  }
  return [...wrapText(left, columns), right.padLeft(columns)];
}

/// Memotong teks per kata agar tiap baris ≤ [columns] karakter.
List<String> wrapText(String text, int columns) {
  final words = text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  final lines = <String>[];
  var current = '';
  for (var word in words) {
    while (word.length > columns) {
      if (current.isNotEmpty) {
        lines.add(current);
        current = '';
      }
      lines.add(word.substring(0, columns));
      word = word.substring(columns);
    }
    if (current.isEmpty) {
      current = word;
    } else if (current.length + 1 + word.length <= columns) {
      current = '$current $word';
    } else {
      lines.add(current);
      current = word;
    }
  }
  if (current.isNotEmpty) lines.add(current);
  return lines.isEmpty ? [''] : lines;
}

/// Printer thermal murah umumnya hanya andal untuk ASCII.
String toPrintable(String text) {
  const map = {
    '×': 'x',
    '−': '-',
    '–': '-',
    '—': '-',
    '·': '-',
    '…': '...',
    '‘': "'",
    '’': "'",
    '“': '"',
    '”': '"',
    'é': 'e',
    'è': 'e',
    'á': 'a',
    'à': 'a',
    'ó': 'o',
    'ú': 'u',
    'í': 'i',
    'ñ': 'n',
  };
  final out = StringBuffer();
  for (final rune in text.runes) {
    final ch = String.fromCharCode(rune);
    if (rune >= 32 && rune < 127) {
      out.write(ch);
    } else if (map.containsKey(ch)) {
      out.write(map[ch]);
    } else if (rune == 0xA0) {
      out.write(' ');
    } else {
      out.write('?');
    }
  }
  return out.toString();
}

String _dateTime(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.day)}/${two(t.month)}/${t.year} ${two(t.hour)}.${two(t.minute)}';
}
