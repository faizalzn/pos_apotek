import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Menyimpan foto produk di folder aplikasi. Database hanya menyimpan nama
/// filenya, sehingga folder ini bisa ikut di-backup utuh.
class PhotoStore {
  PhotoStore(this.directory);

  final Directory directory;

  static const _uuid = Uuid();

  /// Menyalin foto dari [sourcePath] dan mengembalikan nama file barunya.
  Future<String> save(String sourcePath) async {
    await directory.create(recursive: true);
    final ext = sourcePath.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
    final name = '${_uuid.v4()}.$ext';
    await File(sourcePath).copy('${directory.path}/$name');
    return name;
  }

  File fileOf(String name) => File('${directory.path}/$name');

  Future<void> delete(String? name) async {
    if (name == null) return;
    final file = fileOf(name);
    if (await file.exists()) await file.delete();
  }
}

final photoStoreProvider = FutureProvider<PhotoStore>((ref) async {
  final docs = await getApplicationDocumentsDirectory();
  return PhotoStore(Directory('${docs.path}/product_photos'));
});
