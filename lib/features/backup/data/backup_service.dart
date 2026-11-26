import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

import '../../../core/clock.dart';
import '../../../core/database/app_database.dart';
import '../../settings/data/settings_repository.dart' show SettingKeys;

/// Kesalahan yang pesannya boleh langsung ditampilkan ke pengguna.
class BackupException implements Exception {
  const BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Lokasi file aplikasi. Dipisah agar tes bisa memakai folder sementara.
class AppPaths {
  const AppPaths({required this.documents, required this.temp});

  final Directory documents;
  final Directory temp;

  /// Sama dengan lokasi bawaan `driftDatabase(name: 'pos_apotek')`.
  File get database => File('${documents.path}/$databaseFileName');
  Directory get photos => Directory('${documents.path}/product_photos');
  Directory get backups => Directory('${documents.path}/backups');
  File get stateFile => File('${backups.path}/state.json');

  static const databaseFileName = 'pos_apotek.sqlite';
}

final appPathsProvider = FutureProvider<AppPaths>(
  (ref) async => AppPaths(
    documents: await getApplicationDocumentsDirectory(),
    temp: await getTemporaryDirectory(),
  ),
);

/// Ringkasan isi file backup, dibaca dari database di dalamnya.
class BackupInfo {
  const BackupInfo({
    required this.createdAt,
    required this.storeName,
    required this.schemaVersion,
    required this.productCount,
    required this.saleCount,
    required this.userCount,
    required this.photoCount,
    required this.includesPhotos,
  });

  final DateTime createdAt;
  final String storeName;
  final int schemaVersion;
  final int productCount;
  final int saleCount;
  final int userCount;
  final int photoCount;
  final bool includesPhotos;
}

/// File backup yang sudah dibongkar & diperiksa, siap dipulihkan.
class StagedBackup {
  const StagedBackup({required this.directory, required this.info});

  final Directory directory;
  final BackupInfo info;

  File get database => File('${directory.path}/${AppPaths.databaseFileName}');
  Directory get photos => Directory('${directory.path}/product_photos');
}

/// Cadangan yang tersimpan di HP ini (otomatis / sebelum pemulihan).
class LocalBackup {
  const LocalBackup({
    required this.file,
    required this.createdAt,
    required this.kind,
  });

  final File file;
  final DateTime createdAt;
  final LocalBackupKind kind;
}

enum LocalBackupKind {
  daily('Otomatis harian'),
  beforeRestore('Sebelum pemulihan');

  const LocalBackupKind(this.label);
  final String label;
}

/// Catatan backup untuk HP ini. Disimpan di luar database supaya tetap benar
/// setelah data dipulihkan dari file lain.
class BackupState {
  const BackupState({this.lastExportAt, this.lastAutoAt});

  final DateTime? lastExportAt;
  final DateTime? lastAutoAt;

  static BackupState fromJson(Map<String, Object?> json) => BackupState(
    lastExportAt: DateTime.tryParse('${json['lastExportAt']}'),
    lastAutoAt: DateTime.tryParse('${json['lastAutoAt']}'),
  );

  Map<String, Object?> toJson() => {
    'lastExportAt': lastExportAt?.toIso8601String(),
    'lastAutoAt': lastAutoAt?.toIso8601String(),
  };
}

class BackupService {
  BackupService(this._db, this.paths, this._now);

  final AppDatabase _db;
  final AppPaths paths;
  final Clock _now;

  static const formatName = 'pos_apotek_backup';
  static const formatVersion = 1;
  static const _manifestName = 'manifest.json';
  static const _photoPrefix = 'product_photos/';
  static const keepDaily = 7;
  static const keepBeforeRestore = 3;

  /// Batas pengingat: backup keluar HP dianggap "lama" setelah 7 hari.
  static const exportReminderAfter = Duration(days: 7);

  // ---------------------------------------------------------------- membuat

  /// Membuat file backup lengkap (database + foto) di folder sementara,
  /// untuk dikirim/disimpan ke luar HP.
  Future<File> createExport() async {
    final now = _now();
    final name = 'backup_${_slug(await _storeName())}_${_stamp(now)}.zip';
    final file = File('${paths.temp.path}/export/$name');
    // Bersihkan ekspor lama agar folder sementara tidak membengkak.
    final dir = file.parent;
    if (await dir.exists()) await dir.delete(recursive: true);
    await _writeBackup(file, includePhotos: true, now: now);
    return file;
  }

  /// Backup tanpa foto untuk dikirim ke Telegram (kecil, < 50 MB).
  Future<File> createForTelegram() async {
    final now = _now();
    final name = 'backup_${_slug(await _storeName())}_${_stamp(now)}.zip';
    final file = File('${paths.temp.path}/telegram/$name');
    final dir = file.parent;
    if (await dir.exists()) await dir.delete(recursive: true);
    await _writeBackup(file, includePhotos: false, now: now);
    return file;
  }

  /// Cadangan harian otomatis (tanpa foto — foto tidak berubah oleh salah
  /// input). Tidak melakukan apa pun bila cadangan terakhir < 20 jam lalu.
  Future<File?> runDailyBackupIfDue() async {
    final now = _now();
    final state = await readState();
    final last = state.lastAutoAt;
    if (last != null && now.difference(last) < const Duration(hours: 20)) {
      return null;
    }
    final file = await _createLocal(LocalBackupKind.daily, now);
    await _writeState(
      BackupState(lastExportAt: state.lastExportAt, lastAutoAt: now),
    );
    return file;
  }

  /// Cadangan data saat ini sebelum diganti oleh pemulihan.
  Future<File> createBeforeRestore() =>
      _createLocal(LocalBackupKind.beforeRestore, _now());

  Future<File> _createLocal(LocalBackupKind kind, DateTime now) async {
    final prefix = kind == LocalBackupKind.daily ? 'harian' : 'pra-pulih';
    final file = File('${paths.backups.path}/${prefix}_${_stamp(now)}.zip');
    await _writeBackup(file, includePhotos: false, now: now);
    await _prune(
      prefix,
      kind == LocalBackupKind.daily ? keepDaily : keepBeforeRestore,
    );
    return file;
  }

  Future<void> _writeBackup(
    File target, {
    required bool includePhotos,
    required DateTime now,
  }) async {
    await target.parent.create(recursive: true);
    final work = await paths.temp.createTemp('backup_');
    try {
      // VACUUM INTO menghasilkan salinan utuh & konsisten walau aplikasi
      // sedang dipakai (termasuk isi WAL yang belum ditulis ke file utama).
      final copy = File('${work.path}/${AppPaths.databaseFileName}');
      final escaped = copy.path.replaceAll("'", "''");
      await _db.customStatement("VACUUM INTO '$escaped'");

      final photos = <File>[];
      if (includePhotos && await paths.photos.exists()) {
        await for (final e in paths.photos.list()) {
          if (e is File) photos.add(e);
        }
      }
      final manifest = {
        'format': formatName,
        'formatVersion': formatVersion,
        'schemaVersion': _db.schemaVersion,
        'createdAt': now.toIso8601String(),
        'storeName': await _storeName(),
        'includesPhotos': includePhotos,
        'photoCount': photos.length,
      };

      final partial = File('${target.path}.part');
      final zip = ZipFileEncoder()..create(partial.path);
      zip.addArchiveFile(
        ArchiveFile.string(
          _manifestName,
          const JsonEncoder.withIndent('  ').convert(manifest),
        ),
      );
      await zip.addFile(copy, AppPaths.databaseFileName);
      for (final p in photos) {
        await zip.addFile(p, '$_photoPrefix${p.uri.pathSegments.last}');
      }
      await zip.close();
      await partial.rename(target.path);
    } finally {
      await work.delete(recursive: true);
    }
  }

  Future<void> _prune(String prefix, int keep) async {
    final files = await _localFiles(prefix);
    for (final f in files.skip(keep)) {
      await f.delete();
    }
  }

  /// File lokal dengan awalan [prefix], terbaru lebih dulu.
  Future<List<File>> _localFiles(String prefix) async {
    if (!await paths.backups.exists()) return [];
    final files = <File>[
      await for (final e in paths.backups.list())
        if (e is File &&
            e.uri.pathSegments.last.startsWith('${prefix}_') &&
            e.path.endsWith('.zip'))
          e,
    ];
    // Nama berisi tanggal yyyyMMdd_HHmmss, jadi urutan nama = urutan waktu.
    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  Future<List<LocalBackup>> listLocal() async {
    final result = <LocalBackup>[];
    for (final kind in LocalBackupKind.values) {
      final prefix = kind == LocalBackupKind.daily ? 'harian' : 'pra-pulih';
      for (final f in await _localFiles(prefix)) {
        final stamp = _parseStamp(f.uri.pathSegments.last);
        if (stamp != null) {
          result.add(LocalBackup(file: f, createdAt: stamp, kind: kind));
        }
      }
    }
    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  // ---------------------------------------------------------- status/pengingat

  Future<BackupState> readState() async {
    try {
      if (!await paths.stateFile.exists()) return const BackupState();
      final json = jsonDecode(await paths.stateFile.readAsString());
      return BackupState.fromJson((json as Map).cast<String, Object?>());
    } on Object {
      return const BackupState();
    }
  }

  /// Dipanggil setelah backup berhasil dikirim/disimpan ke luar HP.
  Future<void> markExported() async {
    final state = await readState();
    await _writeState(
      BackupState(lastExportAt: _now(), lastAutoAt: state.lastAutoAt),
    );
  }

  Future<void> _writeState(BackupState state) async {
    await paths.backups.create(recursive: true);
    await paths.stateFile.writeAsString(jsonEncode(state.toJson()));
  }

  // -------------------------------------------------------------- memulihkan

  /// Membongkar & memeriksa file backup. Tidak mengubah data apa pun.
  Future<StagedBackup> stage(File source) => stageBackup(
    source,
    paths: paths,
    currentSchemaVersion: _db.schemaVersion,
  );

  Future<String> _storeName() async {
    final row = await (_db.select(
      _db.appSettings,
    )..where((s) => s.key.equals(SettingKeys.storeName))).getSingleOrNull();
    return row?.value ?? '';
  }
}

/// Membongkar [source] ke folder sementara dan memastikan isinya backup
/// POS Apotek yang utuh. Juga dipakai dari wizard setup (sebelum ada data).
Future<StagedBackup> stageBackup(
  File source, {
  required AppPaths paths,
  required int currentSchemaVersion,
}) async {
  final dir = await paths.temp.createTemp('restore_');
  try {
    final input = InputFileStream(source.path);
    Archive archive;
    try {
      archive = ZipDecoder().decodeStream(input);
    } on Object {
      await input.close();
      throw const BackupException(
        'File ini bukan file backup POS Apotek (bukan .zip yang valid).',
      );
    }

    Map<String, Object?>? manifest;
    var hasDb = false;
    var photoCount = 0;
    try {
      for (final entry in archive) {
        if (!entry.isFile) continue;
        final name = entry.name;
        if (name == BackupService._manifestName) {
          manifest = (jsonDecode(utf8.decode(entry.content)) as Map)
              .cast<String, Object?>();
        } else if (name == AppPaths.databaseFileName) {
          await _extract(
            entry,
            File('${dir.path}/${AppPaths.databaseFileName}'),
          );
          hasDb = true;
        } else if (name.startsWith(BackupService._photoPrefix)) {
          final base = name.substring(BackupService._photoPrefix.length);
          // Hanya nama file polos: tolak path seperti "../x" atau "a/b".
          if (base.isEmpty ||
              base.contains('/') ||
              base.contains('\\') ||
              base.startsWith('.')) {
            continue;
          }
          await _extract(entry, File('${dir.path}/product_photos/$base'));
          photoCount++;
        }
      }
    } on FormatException {
      throw const BackupException('File backup rusak dan tidak bisa dibaca.');
    } finally {
      await input.close();
    }

    if (manifest == null ||
        manifest['format'] != BackupService.formatName ||
        !hasDb) {
      throw const BackupException('File ini bukan file backup POS Apotek.');
    }

    final dbFile = File('${dir.path}/${AppPaths.databaseFileName}');
    final info = _inspectDatabase(
      dbFile,
      manifest: manifest,
      photoCount: photoCount,
      currentSchemaVersion: currentSchemaVersion,
    );
    return StagedBackup(directory: dir, info: info);
  } on Object {
    await dir.delete(recursive: true);
    rethrow;
  }
}

Future<void> _extract(ArchiveFile entry, File target) async {
  await target.parent.create(recursive: true);
  final out = OutputFileStream(target.path);
  try {
    entry.writeContent(out);
  } finally {
    await out.close();
  }
}

BackupInfo _inspectDatabase(
  File file, {
  required Map<String, Object?> manifest,
  required int photoCount,
  required int currentSchemaVersion,
}) {
  final sql.Database db;
  try {
    db = sql.sqlite3.open(file.path, mode: sql.OpenMode.readOnly);
  } on Object {
    throw const BackupException('Database di dalam backup rusak.');
  }
  try {
    final check = db.select('PRAGMA integrity_check').first.values.first;
    if (check != 'ok') {
      throw const BackupException('Database di dalam backup rusak.');
    }
    final version = db.select('PRAGMA user_version').first.values.first as int;
    if (version > currentSchemaVersion) {
      throw const BackupException(
        'Backup ini dibuat oleh versi aplikasi yang lebih baru. '
        'Perbarui aplikasi dulu, lalu coba lagi.',
      );
    }
    bool hasTable(String name) => db.select(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
      [name],
    ).isNotEmpty;
    int count(String sqlText) => db.select(sqlText).first.values.first as int;

    if (!hasTable('users') || !hasTable('app_settings')) {
      throw const BackupException('File ini bukan file backup POS Apotek.');
    }
    final owners = count(
      "SELECT COUNT(*) FROM users WHERE role = 'owner' AND is_active = 1",
    );
    if (owners == 0) {
      throw const BackupException(
        'Backup ini tidak berisi akun Pemilik, sehingga tidak bisa dipakai login.',
      );
    }
    final store = db.select('SELECT value FROM app_settings WHERE key = ?', [
      SettingKeys.storeName,
    ]);
    return BackupInfo(
      createdAt:
          DateTime.tryParse('${manifest['createdAt']}') ??
          file.lastModifiedSync(),
      storeName: store.isEmpty ? '' : '${store.first.values.first}',
      schemaVersion: version,
      productCount: hasTable('products')
          ? count('SELECT COUNT(*) FROM products WHERE is_active = 1')
          : 0,
      saleCount: hasTable('sales')
          ? count("SELECT COUNT(*) FROM sales WHERE status = 'completed'")
          : 0,
      userCount: count('SELECT COUNT(*) FROM users WHERE is_active = 1'),
      photoCount: photoCount,
      includesPhotos: manifest['includesPhotos'] == true,
    );
  } on sql.SqliteException {
    throw const BackupException('Database di dalam backup rusak.');
  } finally {
    db.close();
  }
}

/// Mengganti data aplikasi dengan isi [staged].
///
/// **Database aplikasi harus sudah ditutup.** Database diganti dengan
/// `rename` (atomik). Foto hanya diganti bila backup menyertakan foto —
/// cadangan harian tanpa foto mempertahankan foto yang ada.
Future<void> applyRestore(StagedBackup staged, AppPaths paths) async {
  await paths.documents.create(recursive: true);
  final target = paths.database;
  final incoming = File('${target.path}.restoring');
  await staged.database.copy(incoming.path);
  for (final suffix in ['-wal', '-shm', '-journal']) {
    final f = File('${target.path}$suffix');
    if (await f.exists()) await f.delete();
  }
  await incoming.rename(target.path);

  if (staged.info.includesPhotos) {
    final current = paths.photos;
    final old = Directory('${current.path}.lama');
    if (await old.exists()) await old.delete(recursive: true);
    if (await current.exists()) await current.rename(old.path);
    if (await staged.photos.exists()) {
      await current.create(recursive: true);
      await for (final e in staged.photos.list()) {
        if (e is File) {
          await e.copy('${current.path}/${e.uri.pathSegments.last}');
        }
      }
    }
    if (await old.exists()) await old.delete(recursive: true);
  }
  await staged.directory.delete(recursive: true);
}

String _two(int n) => n.toString().padLeft(2, '0');

String _stamp(DateTime t) =>
    '${t.year}${_two(t.month)}${_two(t.day)}_${_two(t.hour)}${_two(t.minute)}${_two(t.second)}';

DateTime? _parseStamp(String fileName) {
  final m = RegExp(r'_(\d{4})(\d{2})(\d{2})_(\d{2})(\d{2})(\d{2})\.zip$')
      .firstMatch(fileName);
  if (m == null) return null;
  final v = [for (var i = 1; i <= 6; i++) int.parse(m.group(i)!)];
  return DateTime(v[0], v[1], v[2], v[3], v[4], v[5]);
}

String _slug(String name) {
  final s = name
      .toLowerCase()
      .replaceAll(RegExp('[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return s.isEmpty ? 'apotek' : (s.length > 30 ? s.substring(0, 30) : s);
}

final backupServiceProvider = FutureProvider<BackupService>(
  (ref) async => BackupService(
    ref.watch(databaseProvider),
    await ref.watch(appPathsProvider.future),
    ref.watch(clockProvider),
  ),
);

final backupStateProvider = FutureProvider<BackupState>(
  (ref) async => (await ref.watch(backupServiceProvider.future)).readState(),
);

final localBackupsProvider = FutureProvider<List<LocalBackup>>(
  (ref) async => (await ref.watch(backupServiceProvider.future)).listLocal(),
);
