import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/clock.dart';
import '../../../core/database/app_database.dart';
import '../../products/data/product_models.dart';

/// Satu baris di keranjang.
class CartLine {
  const CartLine({
    required this.productId,
    required this.productName,
    required this.drugClass,
    required this.photoFile,
    required this.unit,
    required this.baseUnitName,
    required this.availableBase,
    required this.quantity,
    required this.unitPrice,
    this.discount = 0,
  });

  final String productId;
  final String productName;
  final DrugClass drugClass;
  final String? photoFile;
  final ProductUnit unit;
  final String baseUnitName;

  /// Stok layak jual (satuan terkecil) saat barang dimasukkan ke keranjang.
  final int availableBase;
  final int quantity;
  final int unitPrice;

  /// Diskon baris ini dalam rupiah.
  final int discount;

  int get baseQuantity => quantity * unit.multiplier;
  int get gross => unitPrice * quantity;
  int get total => gross - discount;
  bool get priceChanged => unitPrice != unit.sellPrice;

  CartLine copyWith({int? quantity, int? unitPrice, int? discount}) => CartLine(
    productId: productId,
    productName: productName,
    drugClass: drugClass,
    photoFile: photoFile,
    unit: unit,
    baseUnitName: baseUnitName,
    availableBase: availableBase,
    quantity: quantity ?? this.quantity,
    unitPrice: unitPrice ?? this.unitPrice,
    discount: discount ?? this.discount,
  );
}

class Cart {
  const Cart({this.lines = const [], this.discount = 0});

  final List<CartLine> lines;

  /// Diskon total belanja (rupiah).
  final int discount;

  bool get isEmpty => lines.isEmpty;
  int get itemCount => lines.fold(0, (s, l) => s + l.quantity);

  /// Harga × jumlah, sebelum diskon apa pun.
  int get subtotal => lines.fold(0, (s, l) => s + l.gross);
  int get itemDiscount => lines.fold(0, (s, l) => s + l.discount);
  int get total => subtotal - itemDiscount - discount;

  bool get hasOwnerOnlyChanges =>
      discount > 0 || lines.any((l) => l.discount > 0 || l.priceChanged);

  bool get needsPrescription =>
      lines.any((l) => l.drugClass.requiresPrescription);

  /// Jumlah satuan terkecil produk ini yang sudah ada di keranjang.
  int baseQuantityOf(String productId, {int? exceptIndex}) {
    var sum = 0;
    for (var i = 0; i < lines.length; i++) {
      if (i != exceptIndex && lines[i].productId == productId) {
        sum += lines[i].baseQuantity;
      }
    }
    return sum;
  }
}

/// Hasil menambah/mengubah jumlah barang di keranjang.
sealed class CartChange {
  const CartChange();
}

class CartChangeOk extends CartChange {
  const CartChangeOk();
}

class CartChangeNoStock extends CartChange {
  const CartChangeNoStock({required this.availableBase});

  /// Sisa yang masih bisa ditambahkan (satuan terkecil).
  final int availableBase;
}

class CartController extends Notifier<Cart> {
  @override
  Cart build() => const Cart();

  /// Menambah [quantity] [unit] produk. Bila satuan yang sama sudah ada,
  /// jumlahnya ditambah.
  CartChange add(ProductSummary product, ProductUnit unit, {int quantity = 1}) {
    final now = ref.read(clockProvider)();
    final available = product.sellableStock(now);
    final inCart = state.baseQuantityOf(product.product.id);
    if (inCart + quantity * unit.multiplier > available) {
      return CartChangeNoStock(availableBase: available - inCart);
    }

    final lines = [...state.lines];
    final index = lines.indexWhere(
      (l) => l.productId == product.product.id && l.unit.id == unit.id,
    );
    if (index >= 0) {
      lines[index] = lines[index].copyWith(
        quantity: lines[index].quantity + quantity,
      );
    } else {
      lines.add(
        CartLine(
          productId: product.product.id,
          productName: product.product.name,
          drugClass: product.product.drugClass,
          photoFile: product.product.photoFile,
          unit: unit,
          baseUnitName: product.baseUnit.name,
          availableBase: available,
          quantity: quantity,
          unitPrice: unit.sellPrice,
        ),
      );
    }
    state = Cart(lines: lines, discount: state.discount);
    return const CartChangeOk();
  }

  CartChange setQuantity(int index, int quantity) {
    if (quantity <= 0) {
      remove(index);
      return const CartChangeOk();
    }
    final line = state.lines[index];
    final others = state.baseQuantityOf(line.productId, exceptIndex: index);
    if (others + quantity * line.unit.multiplier > line.availableBase) {
      return CartChangeNoStock(availableBase: line.availableBase - others);
    }
    final lines = [...state.lines];
    final updated = line.copyWith(quantity: quantity);
    // Diskon tidak boleh melebihi harga baris setelah jumlah dikurangi.
    lines[index] = updated.discount > updated.gross
        ? updated.copyWith(discount: updated.gross)
        : updated;
    state = Cart(lines: lines, discount: state.discount);
    _clampDiscount();
    return const CartChangeOk();
  }

  /// Mengubah harga & diskon satu baris (hanya Pemilik — diperiksa ulang
  /// saat transaksi disimpan).
  void updatePricing(
    int index, {
    required int unitPrice,
    required int discount,
  }) {
    final lines = [...state.lines];
    final line = lines[index].copyWith(
      unitPrice: unitPrice < 0 ? 0 : unitPrice,
    );
    lines[index] = line.copyWith(discount: discount.clamp(0, line.gross));
    state = Cart(lines: lines, discount: state.discount);
    _clampDiscount();
  }

  void remove(int index) {
    final lines = [...state.lines]..removeAt(index);
    state = Cart(lines: lines, discount: lines.isEmpty ? 0 : state.discount);
    _clampDiscount();
  }

  void setDiscount(int discount) {
    final max = state.subtotal - state.itemDiscount;
    state = Cart(
      lines: state.lines,
      discount: discount.clamp(0, max < 0 ? 0 : max),
    );
  }

  void clear() => state = const Cart();

  void _clampDiscount() {
    final max = state.subtotal - state.itemDiscount;
    if (state.discount > max) {
      state = Cart(lines: state.lines, discount: max < 0 ? 0 : max);
    }
  }
}

final cartProvider = NotifierProvider<CartController, Cart>(CartController.new);
