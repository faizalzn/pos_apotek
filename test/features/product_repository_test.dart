import 'package:flutter_test/flutter_test.dart';
import 'package:pos_apotek/core/database/app_database.dart';
import 'package:pos_apotek/core/format.dart';
import 'package:pos_apotek/features/auth/data/user_repository.dart';
import 'package:pos_apotek/features/products/data/product_models.dart';
import 'package:pos_apotek/features/products/data/product_repository.dart';

import '../helpers.dart';

void main() {
  late AppDatabase db;
  late FakeClock clock;
  late ProductRepository repo;

  setUp(() {
    db = memoryDatabase();
    clock = FakeClock(DateTime(2026, 11, 25, 9));
    repo = ProductRepository(db, clock.call);
  });

  tearDown(() => db.close());

  ProductInput paracetamol({List<UnitInput>? units, String? barcode}) =>
      ProductInput(
        name: 'Paracetamol 500mg',
        genericName: 'Paracetamol',
        category: 'Demam & Nyeri',
        drugClass: DrugClass.bebas,
        minStock: 50,
        units: units ??
            [
              const UnitInput(name: 'Tablet', multiplier: 1, sellPrice: 500),
              UnitInput(
                name: 'Strip',
                multiplier: 10,
                sellPrice: 4500,
                barcode: barcode ?? '8991234567890',
              ),
              const UnitInput(name: 'Box', multiplier: 100, sellPrice: 40000),
            ],
      );

  Future<ProductSummary> summary(String id) async => (await repo.getOne(id))!;

  ProductUnit unit(ProductSummary p, String name) =>
      p.units.firstWhere((u) => u.name == name);

  group('produk', () {
    test('dibuat dengan satuan terurut dari terkecil', () async {
      final p = await repo.create(paracetamol());
      final s = await summary(p.id);
      expect(s.units.map((u) => u.name), ['Tablet', 'Strip', 'Box']);
      expect(s.baseUnit.name, 'Tablet');
      expect(s.stock, 0);
      expect(s.isOutOfStock, isTrue);
    });

    test('validasi satuan', () async {
      Future<void> expectRule(List<UnitInput> units) => expectLater(
            repo.create(paracetamol(units: units)),
            throwsA(isA<UserRuleException>()),
          );
      // Tidak ada satuan terkecil
      await expectRule(
        [const UnitInput(name: 'Strip', multiplier: 10, sellPrice: 1)],
      );
      // Isi kembar
      await expectRule([
        const UnitInput(name: 'Tablet', multiplier: 1, sellPrice: 1),
        const UnitInput(name: 'Strip', multiplier: 10, sellPrice: 1),
        const UnitInput(name: 'Blister', multiplier: 10, sellPrice: 1),
      ]);
      // Nama kembar
      await expectRule([
        const UnitInput(name: 'Tablet', multiplier: 1, sellPrice: 1),
        const UnitInput(name: 'tablet', multiplier: 10, sellPrice: 1),
      ]);
    });

    test('barcode tidak boleh dipakai dua produk', () async {
      await repo.create(paracetamol());
      expect(
        () => repo.create(
          ProductInput(
            name: 'Lain',
            drugClass: DrugClass.bebas,
            units: [
              const UnitInput(
                name: 'Pcs',
                multiplier: 1,
                sellPrice: 1000,
                barcode: '8991234567890',
              ),
            ],
          ),
        ),
        throwsA(
          isA<UserRuleException>().having(
            (e) => e.message,
            'message',
            contains('Paracetamol'),
          ),
        ),
      );
    });

    test('dicari lewat barcode', () async {
      await repo.create(paracetamol());
      final found = await repo.findByBarcode(' 8991234567890 ');
      expect(found?.product.name, 'Paracetamol 500mg');
      expect(found?.unit.name, 'Strip');
      expect(await repo.findByBarcode('000'), isNull);
    });

    test('update: ubah harga, hapus & tambah satuan, barcode milik sendiri boleh',
        () async {
      final p = await repo.create(paracetamol());
      final s = await summary(p.id);
      await repo.update(
        p.id,
        paracetamol(
          units: [
            UnitInput(
              id: unit(s, 'Tablet').id,
              name: 'Tablet',
              multiplier: 1,
              sellPrice: 600,
            ),
            UnitInput(
              id: unit(s, 'Strip').id,
              name: 'Strip',
              multiplier: 10,
              sellPrice: 5000,
              barcode: '8991234567890',
            ),
            const UnitInput(name: 'Blister', multiplier: 20, sellPrice: 9500),
          ],
        ),
      );
      final updated = await summary(p.id);
      expect(updated.units.map((u) => '${u.name}:${u.sellPrice}'), [
        'Tablet:600',
        'Strip:5000',
        'Blister:9500',
      ]);
      expect(unit(updated, 'Tablet').id, unit(s, 'Tablet').id);
    });

    test('arsip', () async {
      final p = await repo.create(paracetamol());
      await repo.setArchived(p.id, archived: true);
      final all = await repo.loadAll();
      final now = clock();
      expect(all.where((x) => ProductFilter.all.matches(x, now)), isEmpty);
      expect(all.where((x) => ProductFilter.archived.matches(x, now)), hasLength(1));
    });

    test('daftar kategori unik & terurut', () async {
      await repo.create(paracetamol());
      await repo.create(
        ProductInput(
          name: 'Vitamin C',
          category: 'Vitamin',
          drugClass: DrugClass.nonObat,
          units: [const UnitInput(name: 'Tablet', multiplier: 1, sellPrice: 1)],
        ),
      );
      await repo.create(
        ProductInput(
          name: 'Ibuprofen',
          category: 'Demam & Nyeri',
          drugClass: DrugClass.bebasTerbatas,
          units: [const UnitInput(name: 'Tablet', multiplier: 1, sellPrice: 1)],
        ),
      );
      expect(await repo.categories(), ['Demam & Nyeri', 'Vitamin']);
    });
  });

  group('stok', () {
    late ProductSummary p;

    setUp(() async {
      final created = await repo.create(paracetamol());
      p = await summary(created.id);
    });

    test('stok masuk dikonversi ke satuan terkecil, harga beli per tablet',
        () async {
      await repo.receiveStock(
        productId: p.product.id,
        unit: unit(p, 'Box'),
        quantity: 2,
        expiryDate: endOfMonth(2027, 8),
        batchNumber: 'B001',
        costPerSelectedUnit: 30000,
      );
      final s = await summary(p.product.id);
      expect(s.stock, 200);
      expect(s.batches.single.costPerUnit, 300);
      expect(s.nearestExpiry, DateTime(2027, 8, 31));
      expect(formatStock(s.stock, s.units), '2 Box');
    });

    test('batch & ED sama digabung, harga beli dirata-rata', () async {
      for (final cost in [30000.0, 40000.0]) {
        await repo.receiveStock(
          productId: p.product.id,
          unit: unit(p, 'Box'),
          quantity: 1,
          expiryDate: endOfMonth(2027, 8),
          batchNumber: 'B001',
          costPerSelectedUnit: cost,
        );
      }
      final s = await summary(p.product.id);
      expect(s.batches, hasLength(1));
      expect(s.stock, 200);
      expect(s.batches.single.costPerUnit, 350);
    });

    test('kasir tanpa harga beli memakai harga beli terakhir', () async {
      await repo.receiveStock(
        productId: p.product.id,
        unit: unit(p, 'Box'),
        quantity: 1,
        expiryDate: endOfMonth(2027, 8),
        costPerSelectedUnit: 30000,
      );
      clock.advance(const Duration(days: 1));
      await repo.receiveStock(
        productId: p.product.id,
        unit: unit(p, 'Strip'),
        quantity: 5,
        expiryDate: endOfMonth(2028, 1),
      );
      final s = await summary(p.product.id);
      expect(s.batches.map((b) => b.costPerUnit), [300, 300]);
    });

    test('FEFO: ED terdekat diambil dulu, batch kedaluwarsa dilewati', () async {
      Future<void> receive(int strips, DateTime? ed, String no) =>
          repo.receiveStock(
            productId: p.product.id,
            unit: unit(p, 'Strip'),
            quantity: strips,
            expiryDate: ed,
            batchNumber: no,
          );
      await receive(1, endOfMonth(2026, 10), 'LAMA'); // sudah kedaluwarsa
      await receive(2, endOfMonth(2028, 1), 'JAUH');
      await receive(1, endOfMonth(2027, 2), 'DEKAT');
      await receive(1, null, 'TANPA-ED');

      final s = await summary(p.product.id);
      expect(s.batches.map((b) => b.batchNumber), [
        'LAMA',
        'DEKAT',
        'JAUH',
        'TANPA-ED',
      ]);
      expect(s.expiryStatus(clock()), ExpiryStatus.expired);
      expect(s.sellableStock(clock()), 40);

      final taken = await repo.consumeFefo(
        productId: p.product.id,
        quantity: 15,
      );
      expect(
        taken.map((a) => '${a.batch.batchNumber}:${a.quantity}'),
        ['DEKAT:10', 'JAUH:5'],
      );

      final after = await summary(p.product.id);
      expect(after.stock, 35); // 10 kedaluwarsa + 15 JAUH + 10 tanpa ED
    });

    test('FEFO menolak bila stok layak jual tidak cukup, tanpa mengubah stok',
        () async {
      await repo.receiveStock(
        productId: p.product.id,
        unit: unit(p, 'Strip'),
        quantity: 1,
        expiryDate: endOfMonth(2027, 8),
      );
      await expectLater(
        repo.consumeFefo(productId: p.product.id, quantity: 11),
        throwsA(
          isA<InsufficientStockException>()
              .having((e) => e.available, 'available', 10),
        ),
      );
      expect((await summary(p.product.id)).stock, 10);
    });

    test('koreksi & buang stok tercatat di riwayat', () async {
      final owner = await UserRepository(db, fastHasher, clock.call)
          .create(name: 'Pemilik', role: UserRole.owner, pin: '482915');
      await repo.receiveStock(
        productId: p.product.id,
        unit: unit(p, 'Strip'),
        quantity: 3,
        expiryDate: endOfMonth(2027, 8),
        userId: owner.id,
      );
      final batch = (await summary(p.product.id)).batches.single;

      clock.advance(const Duration(minutes: 1));
      await repo.adjustBatch(
        batchId: batch.id,
        newQuantity: 28,
        note: 'Stock opname',
        userId: owner.id,
      );
      clock.advance(const Duration(minutes: 1));
      await repo.disposeFromBatch(
        batchId: batch.id,
        quantity: 8,
        note: 'Rusak',
        userId: owner.id,
      );
      expect(
        () => repo.disposeFromBatch(batchId: batch.id, quantity: 999, note: ''),
        throwsA(isA<UserRuleException>()),
      );

      expect((await summary(p.product.id)).stock, 20);
      final history = await repo.watchMovements(p.product.id).first;
      expect(
        history.map((h) => '${h.movement.type.name}:${h.movement.quantity}'),
        ['disposal:-8', 'adjustment:-2', 'stockIn:30'],
      );
      expect(history.first.userName, 'Pemilik');
      expect(history.first.movement.note, 'Rusak');
    });

    test('filter stok menipis & hampir ED', () async {
      await repo.receiveStock(
        productId: p.product.id,
        unit: unit(p, 'Strip'),
        quantity: 4, // 40 ≤ minimum 50
        expiryDate: endOfMonth(2027, 1), // ±2 bulan lagi
      );
      final s = await summary(p.product.id);
      final now = clock();
      expect(ProductFilter.lowStock.matches(s, now), isTrue);
      expect(ProductFilter.nearExpiry.matches(s, now), isTrue);
      expect(ProductFilter.expired.matches(s, now), isFalse);
      expect(ProductFilter.outOfStock.matches(s, now), isFalse);
    });

    test('watchAll memancarkan ulang saat stok berubah', () async {
      final stream = repo.watchAll();
      final expectation = expectLater(
        stream.map((list) => list.single.stock),
        emitsInOrder([0, 10]),
      );
      await Future<void>.delayed(Duration.zero);
      await repo.receiveStock(
        productId: p.product.id,
        unit: unit(p, 'Strip'),
        quantity: 1,
        expiryDate: null,
      );
      await expectation;
    });
  });

  group('format', () {
    test('formatStock', () {
      final units = [
        _unit('Tablet', 1),
        _unit('Strip', 10),
        _unit('Box', 100),
      ];
      expect(formatStock(0, units), 'Habis');
      expect(formatStock(125, units), '1 Box 2 Strip 5 Tablet');
      expect(formatStock(7, units), '7 Tablet');
    });

    test('formatRupiah & ED', () {
      expect(formatRupiah(12500), 'Rp12.500');
      expect(formatExpiry(DateTime(2027, 8, 31)), 'Agu 2027');
      expect(formatExpiry(null), 'Tanpa ED');
      expect(endOfMonth(2028, 2), DateTime(2028, 2, 29));
    });
  });

  group('stok menipis', () {
    Future<ProductSummary> withStock(ProductInput input, int tablets) async {
      final created = await repo.create(input);
      final p = await summary(created.id);
      if (tablets > 0) {
        await repo.receiveStock(
          productId: p.product.id,
          unit: p.baseUnit,
          quantity: tablets,
          expiryDate: endOfMonth(2028, 1),
          costPerSelectedUnit: 300,
        );
      }
      return summary(created.id);
    }

    ProductInput noMin(List<UnitInput> units) => ProductInput(
          name: 'Obat ${units.length}',
          drugClass: DrugClass.bebas,
          units: units,
        );

    const tablet = UnitInput(name: 'Tablet', multiplier: 1, sellPrice: 500);
    const strip = UnitInput(name: 'Strip', multiplier: 10, sellPrice: 4500);

    test('tanpa batas: otomatis kurang dari 1 kemasan terkecil', () async {
      final low = await withStock(noMin([tablet, strip]), 9);
      expect(low.isAutoLowStock, isTrue);
      expect(low.lowStockThreshold, 9);
      expect(low.isLowStock, isTrue);
      expect(ProductFilter.lowStock.matches(low, clock()), isTrue);

      final ok = await withStock(noMin([tablet, strip]), 10);
      expect(ok.isLowStock, isFalse);
    });

    test('habis bukan "menipis" tetapi masuk filter Habis', () async {
      final empty = await withStock(noMin([tablet, strip]), 0);
      expect(empty.isLowStock, isFalse);
      expect(ProductFilter.outOfStock.matches(empty, clock()), isTrue);
    });

    test('satu satuan tanpa batas: tidak diperingatkan sebelum habis', () async {
      final single = await withStock(noMin([tablet]), 1);
      expect(single.lowStockThreshold, 0);
      expect(single.isLowStock, isFalse);
    });

    test('batas diatur Pemilik dipakai (≤ batas)', () async {
      final p = await withStock(paracetamol(), 50); // minStock 50
      expect(p.isAutoLowStock, isFalse);
      expect(p.isLowStock, isTrue);
    });
  });
}


ProductUnit _unit(String name, int multiplier) => ProductUnit(
      id: name,
      productId: 'p',
      name: name,
      multiplier: multiplier,
      sellPrice: 0,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
