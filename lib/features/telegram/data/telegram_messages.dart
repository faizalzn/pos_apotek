import '../../../core/database/app_database.dart';
import '../../../core/format.dart';
import '../../reports/data/report_service.dart';
import '../../sales/data/sale_service.dart';
import '../../shift/data/shift_service.dart';

/// Teks pesan Telegram (HTML). Fungsi murni agar mudah dites.

String escapeHtml(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

String _two(int n) => n.toString().padLeft(2, '0');
String _time(DateTime d) => '${_two(d.hour)}.${_two(d.minute)}';
String _date(DateTime d) =>
    '${d.day} ${monthNames[d.month - 1].substring(0, 3)}';

const _days = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];

String _method(PaymentMethod m) => m == PaymentMethod.qris ? 'QRIS' : 'Tunai';

/// Peringatan stok setelah transaksi.
class StockNote {
  const StockNote({
    required this.name,
    required this.stockText,
    required this.out,
  });
  final String name;
  final String stockText;
  final bool out;
}

String saleMessage(SaleDetail d, {List<StockNote> stock = const []}) {
  final s = d.sale;
  final b = StringBuffer()
    ..writeln(
      '🧾 <b>Penjualan ${s.number}</b> · ${_date(s.createdAt)} ${_time(s.createdAt)}',
    )
    ..writeln('Kasir: ${escapeHtml(d.cashierName)}')
    ..writeln();
  for (final i in d.items) {
    b.writeln(
      '${formatNumber(i.quantity)} ${escapeHtml(i.unitName)} '
      '${escapeHtml(i.productName)} — ${formatRupiah(i.lineTotal)}',
    );
    if (i.discount > 0) b.writeln('   diskon −${formatRupiah(i.discount)}');
  }
  if (s.discount > 0) b.writeln('Diskon belanja −${formatRupiah(s.discount)}');
  b
    ..writeln()
    ..write(
      '<b>Total ${formatRupiah(s.total)}</b> · ${_method(s.paymentMethod)}',
    );
  for (final n in stock) {
    b
      ..writeln()
      ..write(
        n.out
            ? '⛔ Stok habis: ${escapeHtml(n.name)}'
            : '⚠️ Stok menipis: ${escapeHtml(n.name)} (sisa ${escapeHtml(n.stockText)})',
      );
  }
  return b.toString();
}

String voidMessage(SaleDetail d) {
  final s = d.sale;
  final at = s.voidedAt ?? s.updatedAt;
  return [
    '❌ <b>Transaksi dibatalkan</b>',
    '${s.number} · ${formatRupiah(s.total)} (${_method(s.paymentMethod)})',
    'Dijual: ${_date(s.createdAt)} ${_time(s.createdAt)} oleh ${escapeHtml(d.cashierName)}',
    'Dibatalkan: ${_date(at)} ${_time(at)} oleh ${escapeHtml(d.voidedByName ?? '-')}',
    'Alasan: ${escapeHtml(s.voidReason.isEmpty ? '-' : s.voidReason)}',
    if (s.paymentMethod == PaymentMethod.cash)
      'Uang ${formatRupiah(s.total)} dikembalikan dari laci.',
  ].join('\n');
}

String _diff(int d) => switch (d) {
  0 => 'Pas ✅',
  > 0 => 'Lebih ${formatRupiah(d)} ⚠️',
  _ => 'Kurang ${formatRupiah(-d)} ⚠️',
};

String shiftClosedMessage(ShiftSummary s) {
  final sh = s.shift;
  final closed = sh.closedAt ?? sh.updatedAt;
  final b = StringBuffer()
    ..writeln('🔒 <b>Tutup shift · ${escapeHtml(s.openedByName)}</b>')
    ..writeln(
      '${_date(sh.openedAt)} ${_time(sh.openedAt)} – ${_date(closed)} ${_time(closed)}',
    );
  if (s.closedByName != null && s.closedByName != s.openedByName) {
    b.writeln('Ditutup oleh ${escapeHtml(s.closedByName!)}');
  }
  b
    ..writeln()
    ..writeln('Transaksi: ${s.saleCount} · ${formatRupiah(s.totalSales)}')
    ..writeln(
      '  Tunai ${formatRupiah(s.cashSales)} · QRIS ${formatRupiah(s.qrisSales)}',
    );
  if (s.voidCount > 0) b.writeln('  Dibatalkan: ${s.voidCount}');
  b
    ..writeln()
    ..writeln('Modal awal ${formatRupiah(sh.openingCash)}')
    ..writeln('+ Penjualan tunai ${formatRupiah(s.cashSales)}');
  for (final e in s.entries) {
    b.writeln(
      '${e.signedAmount > 0 ? '+' : '−'} ${escapeHtml(e.entry.note)} '
      '${formatRupiah(e.entry.amount)}',
    );
  }
  if (s.refunds > 0) {
    b.writeln('− Pengembalian (batal) ${formatRupiah(s.refunds)}');
  }
  b
    ..writeln('Seharusnya ${formatRupiah(s.expectedCash)}')
    ..writeln('Dihitung ${formatRupiah(sh.countedCash ?? 0)}')
    ..write('<b>Selisih: ${_diff(s.difference ?? 0)}</b>');
  if (sh.closingNote.isNotEmpty) {
    b
      ..writeln()
      ..write('Catatan: ${escapeHtml(sh.closingNote)}');
  }
  return b.toString();
}

String dailyMessage(SalesReport r) {
  final d = r.range.from;
  final b = StringBuffer()
    ..writeln(
      '📊 <b>Ringkasan ${_days[d.weekday - 1]}, ${d.day} '
      '${monthNames[d.month - 1]} ${d.year}</b>',
    );
  if (r.count == 0 && r.voidCount == 0) {
    b.write('Tidak ada transaksi.');
    return b.toString();
  }
  b
    ..writeln('Omzet <b>${formatRupiah(r.revenue)}</b> (${r.count} transaksi)')
    ..writeln(
      'Laba kotor ${formatRupiah(r.grossProfit)} '
      '(${r.margin.toStringAsFixed(1).replaceAll('.', ',')}%)',
    )
    ..writeln('Tunai ${formatRupiah(r.cash)} · QRIS ${formatRupiah(r.qris)}');
  if (r.totalDiscount > 0) b.writeln('Diskon ${formatRupiah(r.totalDiscount)}');
  if (r.voidCount > 0) {
    b.writeln('Dibatalkan ${r.voidCount} (${formatRupiah(r.voidTotal)})');
  }
  if (r.products.isNotEmpty) {
    b
      ..writeln()
      ..writeln('<b>Terlaris</b>');
    for (final (i, p) in r.products.take(5).indexed) {
      final qty = p.quantities.entries
          .map((e) => '${formatNumber(e.value)} ${e.key}')
          .join(', ');
      b.writeln('${i + 1}. ${escapeHtml(p.name)} — ${escapeHtml(qty)}');
    }
  }
  if (r.shifts.isNotEmpty) {
    b
      ..writeln()
      ..writeln('<b>Shift</b>');
    for (final s in r.shifts.reversed) {
      final sh = s.shift;
      b.writeln(
        '• ${escapeHtml(s.openedByName)} ${_time(sh.openedAt)}–'
        '${sh.closedAt == null ? 'sekarang' : _time(sh.closedAt!)} · '
        '${s.isOpen ? 'masih buka' : _diff(s.difference ?? 0)}',
      );
    }
  }
  return b.toString().trimRight();
}
