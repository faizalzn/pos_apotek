import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Gambar struk RGBA (hasil raster PDF, latar transparan) → PNG berlatar putih.
///
/// Tanpa ini latar transparan tampil hitam di galeri/WhatsApp sehingga teks
/// hitam tidak terlihat.
Uint8List receiptPngOnWhite(Uint8List rgba, int width, int height) {
  final src = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: rgba.buffer,
    bytesOffset: rgba.offsetInBytes,
    numChannels: 4,
  );
  final out = img.Image(width: width, height: height)
    ..clear(img.ColorRgb8(255, 255, 255));
  img.compositeImage(out, src);
  return img.encodePng(out);
}
