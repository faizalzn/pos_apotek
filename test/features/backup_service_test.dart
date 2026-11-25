import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:drift/drift.dart' show DatabaseConnection, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_apotek/core/database/app_database.dart';
import 'package:pos_apotek/features/auth/data/recovery_code_service.dart';
import 'package:pos_apotek/features/auth/data/user_repository.dart';
import 'package:pos_apotek/features/backup/data/backup_service.dart';
import 'package:pos_apotek/features/products/data/product_models.dart';
import 'package:pos_apotek/features/products/data/product_repository.dart';
import 'package:pos_apotek/features/settings/data/settings_repository.dart';
import 'package:pos_apotek/features/setup/data/setup_service.dart';

import '../helpers.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory root;
  late AppPaths paths;
  late AppDatabase db;
  late FakeClock clock;
  late BackupService backup;

  AppDatabase openFileDb() => AppDatabase(
    DatabaseConnection(
      NativeDatabase(paths.database),
      closeStreamsSynchronously: true,
    ),
  );

  Future<void> addProduct(AppDatabase db, String name) =>
      ProductRepository(db, clock.call).create(
        ProductInput(
          name: name,
          drugClass: DrugClass.bebas,
          units: [
            const UnitInput(name: 'Tablet', multiplier: 1, sellPrice: 500),
          ],
        ),
      );

  Future<List<String>> productNames(AppDatabase db) async => [
    for (final p in await ProductRepository(db, clock.call).loadAll())
      p.product.name,
  ];

  setUp(() async {
    root = Directory.systemTemp.createTempSync('backup_test_');
    paths = AppPaths(
      documents: Directory('${root.path}/docs')..createSync(),
      temp: Directory('${root.path}/tmp')..createSync(),
    );
    clock = FakeClock(DateTime(2026, 11, 25, 9, 30));
    db = openFileDb();
    final settings = SettingsRepository(db, clock.call);
    final users = UserRepository(db, fastHasher, clock.call);
    await SetupService(
      db,
      settings,
      users,
      RecoveryCodeService(settings, users, fastHasher),
    ).complete(
      store: const StoreProfile(name: 'Apotek Sehat Jaya'),
      ownerName: 'Sari',
      ownerPin: '482915',
    );
    await addProduct(db, 'Paracetamol');
    paths.photos.createSync(recursive: true);
    File('${paths.photos.path}/foto1.jpg').writeAsBytesSync([1, 2, 3]);
    backup = BackupService(db, paths, clock.call);
  });

  tearDown(() async {
    await db.close();
    root.deleteSync(recursive: true);
  });

  test(
    'ekspor berisi manifest, database & foto; isinya bisa diperiksa',
    () async {
      final file = await backup.createExport();
      expect(
        file.uri.pathSegments.last,
        'backup_apotek-sehat-jaya_20261125_093000.zip',
      );

      final archive = ZipDecoder().decodeBytes(file.readAsBytesSync());
      expect(
        archive.files.map((f) => f.name),
        containsAll([
          'manifest.json',
          'pos_apotek.sqlite',
          'product_photos/foto1.jpg',
        ]),
      );
      final manifest = jsonDecode(
        utf8.decode(archive.findFile('manifest.json')!.content),
      );
      expect(manifest['schemaVersion'], 3);

      final staged = await backup.stage(file);
      expect(staged.info.storeName, 'Apotek Sehat Jaya');
      expect(staged.info.productCount, 1);
      expect(staged.info.userCount, 1);
      expect(staged.info.photoCount, 1);
      expect(staged.info.includesPhotos, isTrue);
      expect(staged.info.createdAt, clock());
    },
  );

  test('pulihkan: data & foto kembali seperti saat backup', () async {
    final file = await backup.createExport();

    // Setelah backup: tambah produk & foto lain, hapus foto lama.
    await addProduct(db, 'Amoxicillin');
    File('${paths.photos.path}/foto1.jpg').deleteSync();
    File('${paths.photos.path}/foto2.jpg').writeAsBytesSync([9]);
    expect(await productNames(db), hasLength(2));

    final staged = await backup.stage(file);
    await db.close();
    await applyRestore(staged, paths);

    db = openFileDb();
    expect(await productNames(db), ['Paracetamol']);
    expect(paths.photos.listSync().map((e) => e.uri.pathSegments.last), [
      'foto1.jpg',
    ]);
    expect(staged.directory.existsSync(), isFalse);
  });

  test(
    'cadangan harian: tanpa foto, maks. sekali per hari, simpan 7 terakhir',
    () async {
      expect(await backup.runDailyBackupIfDue(), isNotNull);
      clock.advance(const Duration(hours: 5));
      expect(await backup.runDailyBackupIfDue(), isNull); // belum 20 jam

      for (var i = 0; i < 9; i++) {
        clock.advance(const Duration(days: 1));
        expect(await backup.runDailyBackupIfDue(), isNotNull);
      }
      final local = await backup.listLocal();
      expect(local, hasLength(BackupService.keepDaily));
      expect(local.first.createdAt, clock());
      expect(local.every((b) => b.kind == LocalBackupKind.daily), isTrue);

      final staged = await backup.stage(local.first.file);
      expect(staged.info.includesPhotos, isFalse);
    },
  );

  test('pulihkan cadangan tanpa foto tidak menghapus foto yang ada', () async {
    final daily = (await backup.runDailyBackupIfDue())!;
    final staged = await backup.stage(daily);
    await db.close();
    await applyRestore(staged, paths);
    db = openFileDb();
    expect(File('${paths.photos.path}/foto1.jpg').existsSync(), isTrue);
  });

  test('status ekspor tersimpan di luar database', () async {
    expect((await backup.readState()).lastExportAt, isNull);
    await backup.markExported();
    expect((await backup.readState()).lastExportAt, clock());
  });

  group('file yang ditolak', () {
    Future<File> zipWith(Map<String, List<int>> entries) async {
      final archive = Archive();
      entries.forEach(
        (name, data) => archive.addFile(ArchiveFile.bytes(name, data)),
      );
      final f = File('${root.path}/uji.zip');
      await f.writeAsBytes(ZipEncoder().encodeBytes(archive));
      return f;
    }

    Matcher rejects(String text) => throwsA(
      isA<BackupException>().having(
        (e) => e.message,
        'message',
        contains(text),
      ),
    );

    test('bukan zip', () async {
      final f = File('${root.path}/foto.jpg')..writeAsBytesSync([1, 2, 3, 4]);
      await expectLater(backup.stage(f), rejects('bukan file backup'));
    });

    test('zip lain tanpa manifest', () async {
      await expectLater(
        backup.stage(await zipWith({'dokumen.txt': utf8.encode('halo')})),
        rejects('bukan file backup'),
      );
    });

    test('database rusak', () async {
      await expectLater(
        backup.stage(
          await zipWith({
            'manifest.json': utf8.encode('{"format":"pos_apotek_backup"}'),
            'pos_apotek.sqlite': utf8.encode('bukan database'),
          }),
        ),
        rejects('rusak'),
      );
    });

    test('dari versi aplikasi yang lebih baru', () async {
      final file = await backup.createExport();
      await expectLater(
        stageBackup(file, paths: paths, currentSchemaVersion: 2),
        rejects('versi aplikasi yang lebih baru'),
      );
      // Folder sementara dibersihkan saat gagal.
      expect(
        paths.temp.listSync().where((e) => e.path.contains('restore_')),
        isEmpty,
      );
    });

    test('nama foto berbahaya diabaikan', () async {
      final good = ZipDecoder().decodeBytes(
        (await backup.createExport()).readAsBytesSync(),
      );
      final archive = Archive();
      for (final f in good.files) {
        archive.addFile(ArchiveFile.bytes(f.name, f.content));
      }
      archive.addFile(ArchiveFile.bytes('product_photos/../../jahat.txt', [1]));
      final f = File('${root.path}/campur.zip')
        ..writeAsBytesSync(ZipEncoder().encodeBytes(archive));
      final staged = await backup.stage(f);
      expect(staged.info.photoCount, 1);
      expect(File('${root.path}/jahat.txt').existsSync(), isFalse);
    });
  });
}
