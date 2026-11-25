import '../../../core/format.dart';
import '../../receipt/data/receipt_layout.dart';
import 'shift_service.dart';

/// Ringkasan shift untuk dicetak di printer thermal (arsip kertas).
List<ReceiptLine> buildShiftReceipt(
  ShiftSummary s, {
  required String storeName,
  required int columns,
}) {
  final lines = <ReceiptLine>[];
  void pair(String l, String r, {bool bold = false}) {
    for (final t in twoColumns(l, r, columns)) {
      lines.add(ReceiptLine(t, bold: bold));
    }
  }

  final divider = ReceiptLine('-' * columns);
  if (storeName.isNotEmpty) {
    lines.add(
      ReceiptLine(
        storeName.toUpperCase(),
        align: ReceiptAlign.center,
        bold: true,
      ),
    );
  }
  lines
    ..add(
      const ReceiptLine(
        'RINGKASAN SHIFT',
        align: ReceiptAlign.center,
        bold: true,
        large: true,
      ),
    )
    ..add(divider);
  pair('Kasir', s.openedByName);
  pair('Buka', formatDateTime(s.shift.openedAt));
  if (s.shift.closedAt != null) {
    pair('Tutup', formatDateTime(s.shift.closedAt!));
  }
  if (s.closedByName != null && s.closedByName != s.openedByName) {
    pair('Ditutup oleh', s.closedByName!);
  }
  lines.add(divider);
  pair('Transaksi', '${s.saleCount}');
  pair('Tunai', formatNumber(s.cashSales));
  pair('QRIS', formatNumber(s.qrisSales));
  pair('Total penjualan', formatNumber(s.totalSales), bold: true);
  if (s.voidCount > 0) pair('Dibatalkan', '${s.voidCount}');
  lines.add(divider);
  pair('Modal awal', formatNumber(s.shift.openingCash));
  pair('+ Penjualan tunai', formatNumber(s.cashSales));
  if (s.cashIn > 0) pair('+ Kas masuk', formatNumber(s.cashIn));
  if (s.cashOut > 0) pair('- Kas keluar', formatNumber(s.cashOut));
  if (s.refunds > 0) pair('- Pengembalian', formatNumber(s.refunds));
  pair('Seharusnya', formatNumber(s.expectedCash), bold: true);
  if (s.shift.countedCash != null) {
    pair('Dihitung', formatNumber(s.shift.countedCash!), bold: true);
    final d = s.difference!;
    pair(
      'Selisih',
      d == 0 ? 'Pas' : '${d > 0 ? '+' : '-'}${formatNumber(d.abs())}',
      bold: true,
    );
  }
  if (s.shift.closingNote.isNotEmpty) {
    for (final t in wrapText('Catatan: ${s.shift.closingNote}', columns)) {
      lines.add(ReceiptLine(t));
    }
  }
  if (s.entries.isNotEmpty) {
    lines.add(divider);
    for (final e in s.entries) {
      pair(
        e.entry.note,
        '${e.signedAmount > 0 ? '+' : '-'}${formatNumber(e.entry.amount)}',
      );
    }
  }
  lines
    ..add(divider)
    ..add(const ReceiptLine(''))
    ..add(ReceiptLine('Paraf kasir:${' ' * (columns - 12)}'));
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
