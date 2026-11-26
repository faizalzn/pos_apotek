import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_apotek/core/clock.dart';
import 'package:pos_apotek/core/database/app_database.dart';
import 'package:pos_apotek/core/format.dart';
import 'package:pos_apotek/core/xlsx.dart';
import 'package:pos_apotek/features/auth/data/user_repository.dart';
import 'package:pos_apotek/features/products/data/product_models.dart';
import 'package:pos_apotek/features/products/data/product_repository.dart';
import 'package:pos_apotek/features/sales/application/cart_controller.dart';
import 'package:pos_apotek/features/sales/data/sale_service.dart';
import 'package:pos_apotek/features/shift/data/shift_excel.dart';
import 'package:pos_apotek/features/shift/data/shift_service.dart';

import '../helpers.dart';

/// Isi XML lembar ke-[n] (1 = pertama).
String sheetXml(List<int> xlsx, int n) {
  final zip = ZipDecoder().decodeBytes(xlsx);
  return utf8.decode(zip.findFile('xl/worksheets/sheet$n.xml')!.content);
}

void main() {
  group('penulis xlsx', () {
    test('nama kolom & tanggal Excel', () {
      expect(columnName(0), 'A');
      expect(columnName(25), 'Z');
      expect(columnName(26), 'AA');
      expect(columnName(27), 'AB');
      expect(excelDate(DateTime(2024, 1, 1)), 45292);
      expect(excelDate(DateTime(2024, 1, 1, 18)), 45292.75);
    });

    test('struktur file, teks di-escape, angka & tanggal', () {
      final sheet = XlsxSheet('Uji: a/b', widths: [10], freezeRows: 1)
        ..add(['Nama', 'Jumlah'], style: XlsxStyle.header)
        ..add(['A & <B> "C"', 1500])
        ..add([DateTime(2024, 1, 1), null, 2.5]);
      final bytes = buildXlsx([sheet]);
      final zip = ZipDecoder().decodeBytes(bytes);
      for (final f in [
        '[Content_Types].xml',
        '_rels/.rels',
        'xl/workbook.xml',
        'xl/_rels/workbook.xml.rels',
        'xl/styles.xml',
        'xl/worksheets/sheet1.xml',
      ]) {
        expect(zip.findFile(f), isNotNull, reason: f);
      }
      final workbook = utf8.decode(zip.findFile('xl/workbook.xml')!.content);
      expect(workbook, contains('name="Uji  a b"'));
      final xml = sheetXml(bytes, 1);
      expect(xml, contains('A &amp; &lt;B&gt; &quot;C&quot;'));
      expect(xml, contains('<c r="B2" s="2"><v>1500</v></c>'));
      expect(xml, contains('<c r="A3" s="3"><v>45292.0</v></c>'));
      expect(xml, contains('<c r="C3" s="2"><v>2.5</v></c>'));
      expect(xml, contains('state="frozen"'));
    });
  });

  group('laporan Excel shift', () {
    late AppDatabase db;
    late FakeClock clock;
    late ShiftService shifts;
    late SaleService sales;
    late ProductRepository products;
    late ProviderContainer container;

    setUp(() {
      db = memoryDatabase();
      clock = FakeClock(DateTime(2026, 11, 25, 7));
      shifts = ShiftService(db, clock.call);
      products = ProductRepository(db, clock.call);
      sales = SaleService(db, products, clock.call);
      container = ProviderContainer(
        overrides: [clockProvider.overrideWithValue(clock.call)],
      );
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    test('ringkasan, transaksi, rincian, rekap, kas, dan stok', () async {
      final users = UserRepository(db, fastHasher, clock.call);
      final owner = await users.create(
        name: 'Sari',
        role: UserRole.owner,
        pin: '482915',
      );
      final cashier = await users.create(
        name: 'Dewi',
        role: UserRole.cashier,
        pin: '739164',
      );
      final created = await products.create(
        const ProductInput(
          name: 'Paracetamol & Co',
          drugClass: DrugClass.bebas,
          units: [
            UnitInput(name: 'Tablet', multiplier: 1, sellPrice: 500),
            UnitInput(name: 'Strip', multiplier: 10, sellPrice: 4500),
          ],
        ),
      );
      var p = (await products.getOne(created.id))!;
      await products.receiveStock(
        productId: p.product.id,
        unit: p.baseUnit,
        quantity: 25,
        expiryDate: endOfMonth(2028, 1),
        costPerSelectedUnit: 300,
      );

      final shift = await shifts.open(by: cashier, openingCash: 50000);
      Future<Sale> sell(int strips) async {
        p = (await products.getOne(created.id))!;
        container.read(cartProvider.notifier)
          ..clear()
          ..add(p, p.units.last, quantity: strips);
        final c = container.read(cartProvider);
        return sales.complete(
          cart: c,
          method: PaymentMethod.cash,
          amountPaid: c.total,
          cashier: cashier,
        );
      }

      await sell(1);
      final batal = await sell(1);
      await sales.voidSale(saleId: batal.id, reason: 'salah', by: owner);
      await shifts.addCashEntry(
        type: CashEntryType.cashOut,
        amount: 2000,
        note: 'Beli galon',
        by: cashier,
      );
      await shifts.close(shiftId: shift.id, countedCash: 52500, by: cashier);

      final summary = await shifts.summary(shift.id);
      expect(
        ShiftExcelBuilder.fileName(summary),
        'shift_Dewi_2026-11-25_0700.xlsx',
      );

      final bytes = await ShiftExcelBuilder(
        db,
        shifts,
        products,
        clock.call,
      ).build(shift.id, storeName: 'Apotek Uji');

      final ringkasan = sheetXml(bytes, 1);
      expect(ringkasan, contains('Laporan Shift · Apotek Uji'));
      expect(ringkasan, contains('Seharusnya di laci'));
      expect(ringkasan, contains('<v>52500</v>'));
      expect(ringkasan, contains('Pas'));

      final transaksi = sheetXml(bytes, 2);
      expect(transaksi, contains(batal.number));
      expect(transaksi, contains('Dibatalkan'));
      expect(transaksi, contains('TOTAL (selesai)'));
      expect(transaksi, contains('<v>4500</v>'));

      final rincian = sheetXml(bytes, 3);
      expect(rincian, contains('Paracetamol &amp; Co'));
      expect(rincian, contains('Strip'));

      final rekap = sheetXml(bytes, 4);
      expect(rekap, contains('1 Strip'), reason: 'yang batal tidak dihitung');
      expect(rekap, contains('<v>1500</v>'), reason: 'laba 4500 − 3000');

      final kas = sheetXml(bytes, 5);
      expect(kas, contains('Beli galon'));
      expect(kas, contains('<v>-2000</v>'));

      final stok = sheetXml(bytes, 6);
      expect(stok, contains('1 Strip 5 Tablet'));
      expect(stok, contains('15 Tablet'));

      // Simpan untuk diperiksa dengan program spreadsheet sungguhan.
      final out = Platform.environment['XLSX_OUT'];
      if (out != null) File(out).writeAsBytesSync(bytes);
    });
  });
}
