import 'package:flutter_test/flutter_test.dart';
import 'package:pos_apotek/features/qris/data/qris.dart';

/// QRIS statis contoh (data palsu, bukan milik merchant sungguhan).
String sampleStatic({String extra = ''}) {
  final body = [
    const Tlv('00', '01'),
    const Tlv('01', '11'),
    Tlv(
      '26',
      [
        const Tlv('00', 'ID.CONTOH.WWW'),
        const Tlv('01', '936000000000000001'),
        const Tlv('02', '000000000001'),
        const Tlv('03', 'UMI'),
      ].map((t) => t.encode()).join(),
    ),
    Tlv(
      '51',
      [
        const Tlv('00', 'ID.CO.QRIS.WWW'),
        const Tlv('02', 'ID1020000000001'),
        const Tlv('03', 'UMI'),
      ].map((t) => t.encode()).join(),
    ),
    const Tlv('52', '5912'),
    const Tlv('53', '360'),
    if (extra.isNotEmpty) Tlv('55', extra),
    const Tlv('58', 'ID'),
    const Tlv('59', 'APOTEK CONTOH'),
    const Tlv('60', 'BANDUNG'),
    const Tlv('61', '40111'),
  ].map((t) => t.encode()).join();
  return '${body}6304${qrisCrc('${body}6304')}';
}

void main() {
  test('CRC16-CCITT-FALSE sesuai vektor standar', () {
    expect(qrisCrc('123456789'), '29B1');
    expect(qrisCrc(''), 'FFFF');
  });

  test('membaca QRIS statis', () {
    final q = Qris.parse('  ${sampleStatic()}\n');
    expect(q.merchantName, 'APOTEK CONTOH');
    expect(q.city, 'BANDUNG');
    expect(q.nmid, 'ID1020000000001');
    expect(q.isStatic, isTrue);
    expect(q.amount, isNull);
  });

  test('menolak yang bukan QRIS / rusak', () {
    expect(
      () => Qris.parse('https://contoh.id'),
      throwsA(isA<QrisException>()),
    );
    expect(() => Qris.parse('8991234567890'), throwsA(isA<QrisException>()));
    final s = sampleStatic();
    final broken = s.replaceFirst('APOTEK CONTOH', 'APOTEK CONTOX');
    expect(
      () => Qris.parse(broken),
      throwsA(
        isA<QrisException>().having(
          (e) => e.message,
          'm',
          contains('checksum'),
        ),
      ),
    );
    // QR EMV tanpa ID.CO.QRIS
    final body =
        '000201010211${const Tlv('26', '0011ID.CONTOH').encode()}'
        '5303360${const Tlv('58', 'ID').encode()}6304';
    expect(
      () => Qris.parse('$body${qrisCrc(body)}'),
      throwsA(
        isA<QrisException>().having(
          (e) => e.message,
          'm',
          contains('ID.CO.QRIS'),
        ),
      ),
    );
  });

  test('QRIS dinamis: 01=12, 54=nominal di urutan yang benar, CRC baru', () {
    final q = Qris.parse(sampleStatic());
    final dyn = q.withAmount(15500);
    final d = Qris.parse(dyn); // CRC & format valid
    expect(d.isStatic, isFalse);
    expect(d.amount, 15500);
    expect(d.merchantName, 'APOTEK CONTOH');
    final tags = parseTlv(dyn).map((t) => t.tag).toList();
    expect(tags, [
      '00',
      '01',
      '26',
      '51',
      '52',
      '53',
      '54',
      '58',
      '59',
      '60',
      '61',
      '63',
    ]);
    expect(dyn, contains('5405155005802ID'));

    // Dari QR dinamis pun bisa dibuat ulang dengan nominal lain.
    expect(Qris.parse(d.withAmount(2000)).amount, 2000);
  });

  test('tag tip (55) dibuang agar pelanggan tidak diminta tip', () {
    final q = Qris.parse(sampleStatic(extra: '01'));
    final tags = parseTlv(q.withAmount(1000)).map((t) => t.tag);
    expect(tags, isNot(contains('55')));
  });

  test('nominal tidak valid', () {
    final q = Qris.parse(sampleStatic());
    expect(() => q.withAmount(0), throwsA(isA<QrisException>()));
    expect(() => q.withAmount(-5), throwsA(isA<QrisException>()));
  });
}
