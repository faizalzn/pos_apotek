import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Gaya sel yang tersedia.
enum XlsxStyle { normal, header, money, dateTime, boldMoney, bold, title }

/// Satu sel. Nilai: [String], [int], [double], [DateTime], atau `null`.
class XlsxCell {
  const XlsxCell(this.value, [this.style]);

  final Object? value;
  final XlsxStyle? style;
}

/// Satu lembar kerja.
class XlsxSheet {
  XlsxSheet(this.name, {this.widths = const [], this.freezeRows = 0});

  /// Nama lembar (maks. 31 karakter, tanpa : \ / ? * [ ]).
  final String name;

  /// Lebar kolom (satuan karakter), dari kolom A.
  final List<double> widths;

  /// Baris teratas yang dibekukan (mis. 1 untuk judul kolom).
  final int freezeRows;

  final rows = <List<XlsxCell>>[];

  /// Menambah baris. Nilai biasa otomatis dibungkus jadi [XlsxCell]:
  /// angka bulat → format ribuan, [DateTime] → tanggal & jam.
  void add(List<Object?> values, {XlsxStyle? style}) => rows.add([
    for (final v in values)
      v is XlsxCell ? v : XlsxCell(v, style ?? _defaultStyle(v)),
  ]);

  void blank() => rows.add(const []);

  static XlsxStyle _defaultStyle(Object? v) => switch (v) {
    int() || double() => XlsxStyle.money,
    DateTime() => XlsxStyle.dateTime,
    _ => XlsxStyle.normal,
  };
}

/// Penulis file Excel (.xlsx) sederhana tanpa paket tambahan: zip berisi
/// SpreadsheetML minimal dengan teks *inline* (tanpa sharedStrings).
Uint8List buildXlsx(List<XlsxSheet> sheets) {
  final archive = Archive();
  void put(String path, String content) =>
      archive.addFile(ArchiveFile.bytes(path, utf8.encode(content)));

  put('[Content_Types].xml', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
${[for (var i = 1; i <= sheets.length; i++) '<Override PartName="/xl/worksheets/sheet$i.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'].join('\n')}
</Types>''');

  put('_rels/.rels', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>''');

  put('xl/workbook.xml', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
<sheets>
${[for (final (i, s) in sheets.indexed) '<sheet name="${_esc(_sheetName(s.name))}" sheetId="${i + 1}" r:id="rId${i + 1}"/>'].join('\n')}
</sheets>
</workbook>''');

  put('xl/_rels/workbook.xml.rels', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
${[for (var i = 1; i <= sheets.length; i++) '<Relationship Id="rId$i" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet$i.xml"/>'].join('\n')}
<Relationship Id="rId${sheets.length + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>''');

  // Urutan cellXfs harus sama dengan XlsxStyle.
  put('xl/styles.xml', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<numFmts count="2">
<numFmt numFmtId="164" formatCode="#,##0"/>
<numFmt numFmtId="165" formatCode="dd/mm/yyyy hh:mm"/>
</numFmts>
<fonts count="3">
<font><sz val="11"/><name val="Calibri"/></font>
<font><b/><sz val="11"/><name val="Calibri"/></font>
<font><b/><sz val="14"/><name val="Calibri"/></font>
</fonts>
<fills count="3">
<fill><patternFill patternType="none"/></fill>
<fill><patternFill patternType="gray125"/></fill>
<fill><patternFill patternType="solid"><fgColor rgb="FFCCEDE9"/><bgColor indexed="64"/></patternFill></fill>
</fills>
<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
<cellXfs count="7">
<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
<xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"/>
<xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
<xf numFmtId="165" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
<xf numFmtId="164" fontId="1" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1"/>
<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>
<xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1"/>
</cellXfs>
<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
</styleSheet>''');

  for (final (i, s) in sheets.indexed) {
    put('xl/worksheets/sheet${i + 1}.xml', _sheetXml(s));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

String _sheetXml(XlsxSheet s) {
  final b = StringBuffer()
    ..write(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">',
    );
  if (s.freezeRows > 0) {
    b.write(
      '<sheetViews><sheetView workbookViewId="0">'
      '<pane ySplit="${s.freezeRows}" topLeftCell="A${s.freezeRows + 1}" '
      'activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>',
    );
  }
  if (s.widths.isNotEmpty) {
    b.write('<cols>');
    for (final (i, w) in s.widths.indexed) {
      b.write(
        '<col min="${i + 1}" max="${i + 1}" width="$w" customWidth="1"/>',
      );
    }
    b.write('</cols>');
  }
  b.write('<sheetData>');
  for (final (r, row) in s.rows.indexed) {
    b.write('<row r="${r + 1}">');
    for (final (c, cell) in row.indexed) {
      final ref = '${columnName(c)}${r + 1}';
      final style = (cell.style ?? XlsxStyle.normal).index;
      final st = style == 0 ? '' : ' s="$style"';
      switch (cell.value) {
        case null:
          if (style != 0) b.write('<c r="$ref"$st/>');
        case final num n:
          b.write('<c r="$ref"$st><v>$n</v></c>');
        case final DateTime d:
          b.write('<c r="$ref"$st><v>${excelDate(d)}</v></c>');
        case final Object v:
          b.write(
            '<c r="$ref"$st t="inlineStr"><is><t xml:space="preserve">'
            '${_esc('$v')}</t></is></c>',
          );
      }
    }
    b.write('</row>');
  }
  b.write('</sheetData></worksheet>');
  return b.toString();
}

/// 0 → A, 25 → Z, 26 → AA.
String columnName(int index) {
  var n = index + 1;
  var name = '';
  while (n > 0) {
    final rem = (n - 1) % 26;
    name = String.fromCharCode(65 + rem) + name;
    n = (n - 1) ~/ 26;
  }
  return name;
}

/// Tanggal Excel: hari sejak 30 Des 1899 (waktu setempat, tanpa zona).
double excelDate(DateTime d) {
  final local = DateTime.utc(
    d.year,
    d.month,
    d.day,
    d.hour,
    d.minute,
    d.second,
  );
  return local.difference(DateTime.utc(1899, 12, 30)).inSeconds / 86400;
}

String _sheetName(String name) {
  final clean = name.replaceAll(RegExp(r'[:\\/?*\[\]]'), ' ');
  return clean.length > 31 ? clean.substring(0, 31) : clean;
}

/// Teks aman untuk XML (termasuk membuang karakter kontrol).
String _esc(String s) => s
    .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
