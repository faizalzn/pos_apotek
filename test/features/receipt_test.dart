import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pos_apotek/core/database/app_database.dart';
import 'package:pos_apotek/features/receipt/data/escpos.dart';
import 'package:pos_apotek/features/receipt/data/printer_service.dart';
import 'package:pos_apotek/features/receipt/data/printer_settings.dart';
import 'package:pos_apotek/features/receipt/data/receipt_layout.dart';
import 'package:pos_apotek/features/receipt/data/receipt_service.dart';
import 'package:pos_apotek/features/receipt/presentation/receipt_actions.dart';
import 'package:pos_apotek/features/settings/data/settings_repository.dart';

void main() {
  final created = DateTime(2026, 11, 25, 14, 32);

  Sale sale({
    PaymentMethod method = PaymentMethod.cash,
    SaleStatus status = SaleStatus.completed,
    int itemDiscount = 0,
    int discount = 0,
  }) {
    const subtotal = 4500 + 2400;
    final total = subtotal - itemDiscount - discount;
    return Sale(
      id: 's1',
      number: '261125-0007',
      cashierId: 'u1',
      subtotal: subtotal,
      itemDiscount: itemDiscount,
      discount: discount,
      total: total,
      paymentMethod: method,
      amountPaid: method == PaymentMethod.cash ? 10000 : total,
      change: method == PaymentMethod.cash ? 10000 - total : 0,
      costTotal: 0,
      status: status,
      voidReason: '',
      createdAt: created,
      updatedAt: created,
    );
  }

  SaleItem item(
    String name,
    String unit,
    int qty,
    int price, {
    int discount = 0,
  }) => SaleItem(
    id: name,
    saleId: 's1',
    productId: name,
    unitId: null,
    productName: name,
    unitName: unit,
    multiplier: 1,
    quantity: qty,
    listPrice: price,
    unitPrice: price,
    discount: discount,
    lineTotal: qty * price - discount,
    costTotal: 0,
    createdAt: created,
    updatedAt: created,
  );

  ReceiptData data({Sale? s, bool copy = false, List<SaleItem>? items}) =>
      ReceiptData(
        store: const StoreProfile(
          name: 'Apotek Sehat',
          address: 'Jl. Raya Desa No. 12, Kec. Sukamaju',
          phone: '0812-3456-7890',
        ),
        sale: s ?? sale(),
        items:
            items ??
            [
              item('Paracetamol 500 mg', 'Strip', 1, 4500),
              item('Amoxicillin 500 mg', 'Kapsul', 2, 1200),
            ],
        cashierName: 'Dewi',
        isCopy: copy,
      );

  group('tata letak struk', () {
    test('tidak ada baris yang melebihi lebar kertas', () {
      for (final paper in PaperWidth.values) {
        final lines = buildReceipt(
          data(
            items: [
              item(
                'Obat dengan nama yang sangat panjang sekali hingga harus dipotong',
                'Botol',
                12,
                125000,
                discount: 5000,
              ),
            ],
          ),
          paper.columns,
        );
        for (final l in lines) {
          expect(
            l.text.length,
            lessThanOrEqualTo(paper.columns),
            reason: '"${l.text}"',
          );
        }
      }
    });

    test('isi struk tunai 58 mm', () {
      final text = buildReceipt(data(), 32).map((l) => l.text).toList();
      expect(text.first, 'APOTEK SEHAT');
      expect(text, contains('No                   261125-0007'));
      expect(text, contains('Tanggal         25/11/2026 14.32'));
      expect(text, contains("  1 Strip x 4.500${' ' * 10}4.500"));
      expect(text, contains("  2 Kapsul x 1.200${' ' * 9}2.400"));
      expect(text, contains('TOTAL                    Rp6.900'));
      expect(text, contains('Kembali                    3.100'));
      expect(text, isNot(contains(startsWith('Subtotal'))));
      // Catatan kaki 34 karakter → dibungkus jadi 2 baris di kertas 32 kolom.
      expect(text.sublist(text.length - 2), [
        'Terima kasih, semoga lekas',
        'sembuh.',
      ]);
    });

    test('diskon, QRIS, salinan, dan transaksi batal', () {
      final text = buildReceipt(
        data(
          s: sale(
            method: PaymentMethod.qris,
            itemDiscount: 400,
            discount: 500,
            status: SaleStatus.voided,
          ),
          copy: true,
          items: [
            item('Paracetamol', 'Strip', 1, 4500, discount: 400),
            item('Amoxicillin', 'Kapsul', 2, 1200),
          ],
        ),
        32,
      ).map((l) => l.text).toList();
      expect(text, contains("  Diskon${' ' * 20}-400"));
      expect(text, contains(startsWith('Subtotal')));
      expect(text, contains('TOTAL                    Rp6.000'));
      expect(text, contains('QRIS                       6.000'));
      expect(text, contains('*** SALINAN ***'));
      expect(text, contains('*** TRANSAKSI DIBATALKAN ***'));
    });

    test('teks WhatsApp dalam blok monospace', () {
      final t = receiptAsText(buildReceipt(data(), 32), 32);
      expect(t, startsWith('```\n'));
      expect(t, endsWith('```'));
      expect(t, contains('          APOTEK SEHAT'));
    });

    test('pembungkus kata & karakter non-ASCII', () {
      expect(wrapText('satu dua tiga empat', 9), ['satu dua', 'tiga', 'empat']);
      expect(wrapText('abcdefghij', 4), ['abcd', 'efgh', 'ij']);
      expect(twoColumns('Kiri', 'Kanan', 12), ['Kiri   Kanan']);
      expect(twoColumns('Kiri panjang', 'Kanan', 12), [
        'Kiri panjang',
        '       Kanan',
      ]);
      expect(toPrintable('2 × Rp1.000 · Café'), '2 x Rp1.000 - Cafe');
    });
  });

  group('ESC/POS', () {
    test('struk diawali reset dan diakhiri potong kertas', () {
      final bytes = receiptToEscPos(
        buildReceipt(data(), 32),
        paper: PaperWidth.mm58,
      );
      expect(bytes.sublist(0, 2), [0x1B, 0x40]);
      expect(bytes.sublist(bytes.length - 4), [0x1D, 0x56, 0x42, 0x00]);
      expect(String.fromCharCodes(bytes), contains('Paracetamol 500 mg'));
      expect(bytes.every((b) => b < 0x80), isTrue, reason: 'hanya ASCII');
    });

    test('gambar diubah jadi bit hitam-putih; transparan = putih', () {
      final image = img.Image(width: 10, height: 1, numChannels: 4);
      for (var x = 0; x < 10; x++) {
        image.setPixelRgba(x, 0, 255, 255, 255, 255);
      }
      image.setPixelRgba(0, 0, 0, 0, 0, 255); // hitam
      image.setPixelRgba(9, 0, 0, 0, 0, 255); // hitam
      image.setPixelRgba(1, 0, 0, 0, 0, 0); // hitam tapi transparan
      expect(monochrome(image), Uint8List.fromList([0x80, 0x40]));
    });

    test('logo dikecilkan ke lebar maksimum dan dikirim per potongan', () {
      final logo = img.Image(width: 800, height: 400);
      final bytes = receiptToEscPos([], paper: PaperWidth.mm58, logo: logo);
      // Lebar 60% dari 384 titik = 230 → 29 byte per baris.
      final header = [0x1D, 0x76, 0x30, 0x00, 29, 0];
      var count = 0;
      for (var i = 0; i + header.length <= bytes.length; i++) {
        var match = true;
        for (var j = 0; j < header.length; j++) {
          if (bytes[i + j] != header[j]) {
            match = false;
            break;
          }
        }
        if (match) count++;
      }
      expect(count, (115 / 64).ceil()); // tinggi 115 → 2 potongan
    });
  });

  test('PDF struk berhasil dibuat', () async {
    final pdf = await receiptPdf(
      buildReceipt(data(), 32),
      paper: PaperWidth.mm58,
    );
    expect(String.fromCharCodes(pdf.sublist(0, 5)), '%PDF-');
  });

  test('nomor WhatsApp', () {
    expect(normalizeWhatsAppNumber('0812-3456-7890'), '6281234567890');
    expect(normalizeWhatsAppNumber('+62 812 3456 7890'), '6281234567890');
    expect(normalizeWhatsAppNumber('81234567890'), '6281234567890');
    expect(normalizeWhatsAppNumber('123'), isNull);
    expect(normalizeWhatsAppNumber(''), isNull);
  });

  group('printer WiFi', () {
    test('byte terkirim utuh ke port printer', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final received = <int>[];
      final done = server.first.then((socket) async {
        await socket.forEach(received.addAll);
      });
      final bytes = receiptToEscPos(
        buildReceipt(data(), 48),
        paper: PaperWidth.mm80,
      );
      await PrinterService().send(
        PrinterSettings(
          type: PrinterType.network,
          host: '127.0.0.1',
          port: server.port,
        ),
        bytes,
      );
      await done;
      await server.close();
      expect(received, bytes);
    });

    test('printer tidak terjangkau → pesan jelas', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;
      await server.close();
      await expectLater(
        PrinterService().send(
          PrinterSettings(
            type: PrinterType.network,
            host: '127.0.0.1',
            port: port,
          ),
          Uint8List(1),
        ),
        throwsA(
          isA<PrinterException>().having(
            (e) => e.message,
            'message',
            contains('WiFi yang sama'),
          ),
        ),
      );
    });
  });

  test('pengaturan printer tersimpan & terbaca kembali', () {
    const s = PrinterSettings(
      type: PrinterType.bluetooth,
      btAddress: 'AA:BB',
      btName: 'RPP02',
      paper: PaperWidth.mm80,
      autoPrint: false,
    );
    final back = PrinterSettings.fromMap(s.toMap());
    expect(back.type, PrinterType.bluetooth);
    expect(back.btName, 'RPP02');
    expect(back.paper, PaperWidth.mm80);
    expect(back.autoPrint, isFalse);
    expect(back.isReady, isTrue);
    expect(PrinterSettings.fromMap(const {}).type, PrinterType.none);
    expect(PrinterSettings.fromMap(const {}).autoPrint, isTrue);
  });
}
