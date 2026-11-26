/// QRIS (standar EMVCo Merchant-Presented QR). Lihat ADR-0002.
///
/// Payload berupa rangkaian TLV: `ID(2) PANJANG(2) NILAI`, diakhiri tag `63`
/// berisi CRC16-CCITT (poly 0x1021, awal 0xFFFF) dari seluruh teks sebelumnya
/// termasuk "6304".
library;

class QrisException implements Exception {
  const QrisException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Satu elemen TLV.
class Tlv {
  const Tlv(this.tag, this.value);
  final String tag;
  final String value;

  String encode() => '$tag${value.length.toString().padLeft(2, '0')}$value';
}

/// CRC16-CCITT-FALSE, 4 digit heksadesimal huruf besar.
String qrisCrc(String data) {
  var crc = 0xFFFF;
  for (final c in data.codeUnits) {
    crc ^= c << 8;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 0x8000) != 0 ? ((crc << 1) ^ 0x1021) : (crc << 1);
      crc &= 0xFFFF;
    }
  }
  return crc.toRadixString(16).toUpperCase().padLeft(4, '0');
}

List<Tlv> parseTlv(String data) {
  final out = <Tlv>[];
  var i = 0;
  while (i < data.length) {
    if (i + 4 > data.length) throw const QrisException('Data QR terpotong');
    final tag = data.substring(i, i + 2);
    final len = int.tryParse(data.substring(i + 2, i + 4));
    if (len == null || i + 4 + len > data.length) {
      throw const QrisException('Data QR tidak sesuai format QRIS');
    }
    out.add(Tlv(tag, data.substring(i + 4, i + 4 + len)));
    i += 4 + len;
  }
  return out;
}

/// QRIS milik merchant yang sudah diperiksa.
class Qris {
  Qris._(this.payload, this._tags);

  /// Memeriksa teks hasil scan. Melempar [QrisException] bila bukan QRIS.
  factory Qris.parse(String raw) {
    final payload = raw.trim();
    if (!payload.startsWith('000201')) {
      throw const QrisException(
        'Ini bukan kode QRIS. Pastikan yang di-scan adalah QRIS apotek.',
      );
    }
    final tags = parseTlv(payload);
    if (tags.isEmpty || tags.last.tag != '63' || tags.last.value.length != 4) {
      throw const QrisException('Kode QRIS tidak lengkap (tanpa checksum).');
    }
    final body = payload.substring(0, payload.length - 4);
    if (qrisCrc(body) != tags.last.value.toUpperCase()) {
      throw const QrisException(
        'Kode QRIS rusak (checksum salah). Coba scan ulang dengan lebih jelas.',
      );
    }
    final qris = Qris._(payload, tags);
    if (!qris._hasQrisMerchant) {
      throw const QrisException(
        'Kode QR ini bukan QRIS Indonesia (tidak ada ID.CO.QRIS).',
      );
    }
    if (qris.value('58') != 'ID' || qris.value('53') != '360') {
      throw const QrisException('QRIS harus berupa QRIS Indonesia (Rupiah).');
    }
    return qris;
  }

  final String payload;
  final List<Tlv> _tags;

  String? value(String tag) =>
      _tags.where((t) => t.tag == tag).firstOrNull?.value;

  bool get _hasQrisMerchant => _tags.any((t) {
    final n = int.tryParse(t.tag) ?? 0;
    return n >= 26 && n <= 51 && t.value.toUpperCase().contains('ID.CO.QRIS');
  });

  String get merchantName => value('59') ?? '';
  String get city => value('60') ?? '';

  /// National Merchant ID (NMID), bila ada (tag 51 sub-tag 02).
  String? get nmid {
    for (final t in _tags.where((t) => t.tag == '51')) {
      try {
        return parseTlv(t.value).where((s) => s.tag == '02').firstOrNull?.value;
      } on QrisException {
        return null;
      }
    }
    return null;
  }

  /// QR statis (`11`) atau sudah berisi nominal (`12`).
  bool get isStatic => value('01') != '12';

  /// Nominal yang sudah tertanam (QR dinamis), bila ada.
  int? get amount => int.tryParse((value('54') ?? '').split('.').first);

  /// QRIS dinamis berisi [amount] rupiah:
  /// tag 01 → `12`, tag 54 = nominal, tag tip (55–57) dibuang, CRC dihitung ulang.
  String withAmount(int amount) {
    if (amount <= 0) throw const QrisException('Nominal harus lebih dari 0');
    final text = '$amount';
    if (text.length > 13) throw const QrisException('Nominal terlalu besar');
    final tags = [
      for (final t in _tags)
        if (!const {'54', '55', '56', '57', '63'}.contains(t.tag))
          t.tag == '01' ? const Tlv('01', '12') : t,
    ];
    if (!tags.any((t) => t.tag == '01')) tags.insert(1, const Tlv('01', '12'));
    // Sisipkan 54 sebelum tag pertama yang lebih besar (urutan menaik).
    final at = tags.indexWhere((t) => (int.tryParse(t.tag) ?? 0) > 54);
    tags.insert(at < 0 ? tags.length : at, Tlv('54', text));
    final body = '${tags.map((t) => t.encode()).join()}6304';
    return '$body${qrisCrc(body)}';
  }
}
