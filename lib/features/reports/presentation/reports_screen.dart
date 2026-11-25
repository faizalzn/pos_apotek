import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/format.dart';
import '../../../core/widgets/common.dart';
import '../../shift/presentation/shift_screen.dart';
import '../data/report_service.dart';

enum _Period {
  today('Hari ini'),
  yesterday('Kemarin'),
  week('7 hari'),
  month('Bulan ini'),
  lastMonth('Bulan lalu'),
  custom('Pilih tanggal');

  const _Period(this.label);
  final String label;
}

/// Laporan penjualan (khusus Pemilik).
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  _Period _period = _Period.today;
  ReportRange? _custom;

  ReportRange _range(DateTime today) => switch (_period) {
    _Period.today => ReportRange.day(today),
    _Period.yesterday => ReportRange.day(
      today.subtract(const Duration(days: 1)),
    ),
    _Period.week => ReportRange.days(
      today.subtract(const Duration(days: 6)),
      today,
    ),
    _Period.month => ReportRange.month(today),
    _Period.lastMonth => ReportRange.month(
      DateTime(today.year, today.month - 1),
    ),
    _Period.custom => _custom ?? ReportRange.day(today),
  };

  Future<void> _pickRange(DateTime today) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: today,
      initialDateRange: _custom == null
          ? DateTimeRange(
              start: today.subtract(const Duration(days: 6)),
              end: today,
            )
          : DateTimeRange(
              start: _custom!.from,
              end: _custom!.to.subtract(const Duration(days: 1)),
            ),
    );
    if (picked != null) {
      setState(() {
        _custom = ReportRange.days(picked.start, picked.end);
        _period = _Period.custom;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(todayProvider);
    final range = _range(today);
    final report = ref.watch(salesReportProvider(range));

    return Scaffold(
      appBar: AppBar(title: const Text('Laporan')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          ContentWidth(
            maxWidth: 840,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final p in _Period.values)
                        ChoiceChip(
                          label: Text(p.label),
                          selected: _period == p,
                          onSelected: (_) => p == _Period.custom
                              ? _pickRange(today)
                              : setState(() => _period = p),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    _rangeLabel(range),
                    key: const Key('report-range'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                switch (report) {
                  AsyncData(:final value) => _ReportBody(report: value),
                  AsyncError(:final error) => Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('$error'),
                  ),
                  _ => const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                },
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _date(DateTime d) => '${d.day} ${monthNames[d.month - 1]} ${d.year}';

String _rangeLabel(ReportRange r) {
  final last = r.to.subtract(const Duration(days: 1));
  return r.dayCount <= 1 ? _date(r.from) : '${_date(r.from)} – ${_date(last)}';
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({required this.report});

  final SalesReport report;

  @override
  Widget build(BuildContext context) {
    final r = report;
    final theme = Theme.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 600;

    Widget section(String title, List<Widget> children) => Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );

    Widget row(String label, String value, {Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: theme.textTheme.bodyLarge?.copyWith(color: color)),
        ],
      ),
    );

    if (r.count == 0 && r.voidCount == 0) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: Text('Belum ada transaksi pada periode ini')),
      );
    }

    final stats = [
      _Stat('Omzet', formatRupiah(r.revenue), key: const Key('stat-revenue')),
      _Stat(
        'Laba kotor',
        formatRupiah(r.grossProfit),
        hint: '${r.margin.toStringAsFixed(1)}% dari omzet',
        key: const Key('stat-profit'),
      ),
      _Stat('Transaksi', formatNumber(r.count)),
      _Stat('Rata-rata', formatRupiah(r.averageSale), hint: 'per transaksi'),
    ];
    final maxDay = r.days.fold(0, (m, d) => d.revenue > m ? d.revenue : m);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: wide ? 4 : 2,
            childAspectRatio: wide ? 1.6 : 1.5,
            children: stats,
          ),
        ),
        section('Pembayaran', [
          row('Tunai', formatRupiah(r.cash)),
          row('QRIS', formatRupiah(r.qris)),
          if (r.revenue > 0) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: r.cash / r.revenue,
                minHeight: 10,
                backgroundColor: theme.colorScheme.tertiaryContainer,
              ),
            ),
          ],
        ]),
        section('Diskon & pembatalan', [
          row('Diskon barang', formatRupiah(r.itemDiscount)),
          row('Diskon total belanja', formatRupiah(r.discount)),
          row(
            'Transaksi dibatalkan',
            r.voidCount == 0
                ? '-'
                : '${r.voidCount} (${formatRupiah(r.voidTotal)})',
            color: r.voidCount > 0 ? theme.colorScheme.error : null,
          ),
        ]),
        if (r.range.dayCount > 1 && r.days.isNotEmpty)
          section('Per hari', [
            for (final d in r.days)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 64,
                      child: Text(
                        '${d.day.day} ${monthNames[d.day.month - 1]}',
                      ),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: maxDay == 0 ? 0 : d.revenue / maxDay,
                          minHeight: 14,
                          backgroundColor:
                              theme.colorScheme.surfaceContainerHighest,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 104,
                      child: Text(
                        formatRupiah(d.revenue),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              ),
          ]),
        if (r.products.isNotEmpty)
          section('Obat terlaris', [
            for (final (i, p) in r.products.take(10).indexed)
              _ProductRow(rank: i + 1, product: p),
            if (r.products.length > 10)
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _AllProductsScreen(report: r),
                  ),
                ),
                child: Text('Lihat semua (${r.products.length} produk)'),
              ),
            Text(
              'Omzet per produk belum dikurangi diskon total belanja.',
              style: theme.textTheme.bodySmall,
            ),
          ]),
        if (r.cashiers.isNotEmpty)
          section('Per kasir', [
            for (final c in r.cashiers)
              row('${c.name} · ${c.count} transaksi', formatRupiah(c.revenue)),
          ]),
        if (r.shifts.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Shift', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                for (final s in r.shifts) ShiftTile(summary: s),
              ],
            ),
          ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, {this.hint, super.key});

  final String label;
  final String value;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            if (hint != null)
              Text(
                hint!,
                style: theme.textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.rank, required this.product});

  final int rank;
  final ProductSales product;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final qty = product.quantities.entries
        .map((e) => '${formatNumber(e.value)} ${e.key}')
        .join(', ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text('$rank.', style: theme.textTheme.titleSmall),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.name, style: theme.textTheme.titleSmall),
                Text(qty, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(formatRupiah(product.revenue)),
              Text(
                'laba ${formatRupiah(product.profit)}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AllProductsScreen extends StatelessWidget {
  const _AllProductsScreen({required this.report});

  final SalesReport report;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('Penjualan produk · ${_rangeLabel(report.range)}'),
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final (i, p) in report.products.indexed)
          _ProductRow(rank: i + 1, product: p),
      ],
    ),
  );
}
