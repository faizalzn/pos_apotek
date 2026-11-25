import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'database/app_database.dart';

final _rupiah = NumberFormat.currency(locale: 'id', symbol: 'Rp', decimalDigits: 0);
final _thousands = NumberFormat.decimalPattern('id');

/// `12500` → `Rp12.500`.
String formatRupiah(num value) => _rupiah.format(value);

/// `12500` → `12.500`.
String formatNumber(num value) => _thousands.format(value);

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', //
  'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
];

const monthNames = [
  'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni', //
  'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember',
];

/// Tanggal kedaluwarsa ditampilkan bulan & tahun saja, sesuai kemasan: `Agu 2027`.
String formatExpiry(DateTime? date) =>
    date == null ? 'Tanpa ED' : '${_months[date.month - 1]} ${date.year}';

/// `25 Nov 2026, 14.05`.
String formatDateTime(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.day} ${_months[d.month - 1]} ${d.year}, ${two(d.hour)}.${two(d.minute)}';
}

/// Hari terakhir pada bulan tersebut (ED di kemasan umumnya hanya bulan/tahun).
DateTime endOfMonth(int year, int month) => DateTime(year, month + 1, 0);

/// Jumlah stok dalam satuan terkecil → teks yang mudah dibaca,
/// mis. 125 tablet dengan Box(100) & Strip(10) → `1 Box 2 Strip 5 Tablet`.
String formatStock(int quantity, List<ProductUnit> units) {
  if (units.isEmpty) return '$quantity';
  if (quantity == 0) return 'Habis';
  final sorted = [...units]..sort((a, b) => b.multiplier.compareTo(a.multiplier));
  final negative = quantity < 0;
  var rest = quantity.abs();
  final parts = <String>[];
  for (final unit in sorted) {
    final count = rest ~/ unit.multiplier;
    if (count > 0) {
      parts.add('$count ${unit.name}');
      rest -= count * unit.multiplier;
    }
  }
  return '${negative ? '−' : ''}${parts.join(' ')}';
}

/// Input angka dengan pemisah ribuan otomatis: `12500` → `12.500`.
class ThousandsInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return const TextEditingValue();
    final formatted = _thousands.format(int.parse(digits));
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

/// Kebalikan dari [ThousandsInputFormatter]: `12.500` → `12500`.
int parseNumber(String text) =>
    int.tryParse(text.replaceAll(RegExp(r'\D'), '')) ?? 0;
