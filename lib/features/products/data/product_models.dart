import '../../../core/database/app_database.dart';

/// Bawaan: peringatan "hampir kedaluwarsa" muncul 90 hari (±3 bulan) sebelum ED.
const defaultNearExpiryDays = 90;

/// Pilihan lama peringatan ED yang ditawarkan ke pengguna (hari → label).
const nearExpiryChoices = {
  30: '1 bulan',
  60: '2 bulan',
  90: '3 bulan',
  180: '6 bulan',
  365: '12 bulan',
};

String nearExpiryLabel(int days) => nearExpiryChoices[days] ?? '$days hari';

enum ExpiryStatus { none, ok, soon, expired }

ExpiryStatus expiryStatusOf(
  DateTime? expiry,
  DateTime now, {
  int windowDays = defaultNearExpiryDays,
}) {
  if (expiry == null) return ExpiryStatus.none;
  final today = DateTime(now.year, now.month, now.day);
  if (expiry.isBefore(today)) return ExpiryStatus.expired;
  if (expiry.isBefore(today.add(Duration(days: windowDays)))) {
    return ExpiryStatus.soon;
  }
  return ExpiryStatus.ok;
}

/// Data satuan dari formulir produk.
class UnitInput {
  const UnitInput({
    this.id,
    required this.name,
    required this.multiplier,
    required this.sellPrice,
    this.barcode,
  });

  /// `null` untuk satuan baru.
  final String? id;
  final String name;
  final int multiplier;
  final int sellPrice;
  final String? barcode;
}

/// Data dari formulir produk.
class ProductInput {
  const ProductInput({
    required this.name,
    this.genericName = '',
    this.category = '',
    required this.drugClass,
    this.minStock = 0,
    this.nearExpiryDays,
    this.photoFile,
    required this.units,
  });

  final String name;
  final String genericName;
  final String category;
  final DrugClass drugClass;
  final int minStock;

  /// `null` = ikuti pengaturan umum.
  final int? nearExpiryDays;
  final String? photoFile;
  final List<UnitInput> units;
}

/// Produk beserta satuan & ringkasan stoknya.
class ProductSummary {
  ProductSummary({
    required this.product,
    required List<ProductUnit> units,
    required this.batches,
    this.defaultExpiryDays = defaultNearExpiryDays,
  }) : units = [...units]..sort((a, b) => a.multiplier.compareTo(b.multiplier));

  final Product product;

  /// Urut dari satuan terkecil.
  final List<ProductUnit> units;

  /// StockBatch yang masih ada stoknya, urut ED terdekat (tanpa ED paling akhir).
  final List<StockBatch> batches;

  /// Pengaturan umum peringatan ED (hari).
  final int defaultExpiryDays;

  /// Lama peringatan ED yang berlaku untuk produk ini.
  int get nearExpiryDays => product.nearExpiryDays ?? defaultExpiryDays;

  ExpiryStatus batchStatus(StockBatch b, DateTime now) =>
      expiryStatusOf(b.expiryDate, now, windowDays: nearExpiryDays);

  ProductUnit get baseUnit => units.first;

  /// Total stok dalam satuan terkecil.
  int get stock => batches.fold(0, (sum, b) => sum + b.quantity);

  /// Stok yang boleh dijual (tidak termasuk batch kedaluwarsa).
  int sellableStock(DateTime now) => batches
      .where((b) => expiryStatusOf(b.expiryDate, now) != ExpiryStatus.expired)
      .fold(0, (sum, b) => sum + b.quantity);

  DateTime? get nearestExpiry =>
      batches.map((b) => b.expiryDate).whereType<DateTime>().firstOrNull;

  bool get isLowStock =>
      product.minStock > 0 && stock > 0 && stock <= product.minStock;

  bool get isOutOfStock => stock <= 0;

  ExpiryStatus expiryStatus(DateTime now) {
    var worst = ExpiryStatus.none;
    for (final b in batches) {
      final s = batchStatus(b, now);
      if (s.index > worst.index) worst = s;
    }
    return worst;
  }

  /// Harga beli rata-rata per satuan terkecil dari stok yang ada.
  double get averageCost {
    final qty = stock;
    if (qty <= 0) return batches.isEmpty ? 0 : batches.last.costPerUnit;
    return batches.fold(0.0, (s, b) => s + b.costPerUnit * b.quantity) / qty;
  }
}

enum ProductFilter {
  all('Semua'),
  lowStock('Stok menipis'),
  outOfStock('Habis'),
  nearExpiry('Hampir ED'),
  expired('Kedaluwarsa'),
  archived('Diarsipkan');

  const ProductFilter(this.label);
  final String label;

  bool matches(ProductSummary p, DateTime now) => switch (this) {
    ProductFilter.all => p.product.isActive,
    ProductFilter.lowStock => p.product.isActive && p.isLowStock,
    ProductFilter.outOfStock => p.product.isActive && p.isOutOfStock,
    ProductFilter.nearExpiry =>
      p.product.isActive && p.expiryStatus(now) == ExpiryStatus.soon,
    ProductFilter.expired =>
      p.product.isActive && p.expiryStatus(now) == ExpiryStatus.expired,
    ProductFilter.archived => !p.product.isActive,
  };
}

/// Bagian stok yang diambil dari satu batch.
class BatchAllocation {
  const BatchAllocation({required this.batch, required this.quantity});
  final StockBatch batch;
  final int quantity;
}

class InsufficientStockException implements Exception {
  const InsufficientStockException({
    required this.requested,
    required this.available,
  });

  final int requested;
  final int available;

  @override
  String toString() =>
      'Stok tidak cukup: diminta $requested, tersedia $available';
}

/// Riwayat stok beserta nama pengguna yang mencatatnya.
class MovementEntry {
  const MovementEntry({required this.movement, this.userName, this.batch});
  final StockMovement movement;
  final String? userName;
  final StockBatch? batch;
}
