import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pos_apotek/features/receipt/data/receipt_image.dart';

void main() {
  test('latar transparan menjadi putih, teks hitam tetap hitam', () {
    // 2×1 piksel: transparan, hitam pekat
    final rgba = Uint8List.fromList([0, 0, 0, 0, 0, 0, 0, 255]);
    final png = img.decodePng(receiptPngOnWhite(rgba, 2, 1))!;
    expect(png.numChannels, 3);
    final bg = png.getPixel(0, 0);
    final ink = png.getPixel(1, 0);
    expect([bg.r, bg.g, bg.b], [255, 255, 255]);
    expect([ink.r, ink.g, ink.b], [0, 0, 0]);
  });
}
