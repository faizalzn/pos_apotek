import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pos_apotek/app.dart';
import 'package:pos_apotek/core/clock.dart';
import 'package:pos_apotek/core/database/app_database.dart';
import 'package:pos_apotek/core/security/pin_hasher.dart';
import 'package:pos_apotek/features/auth/data/recovery_code_service.dart';
import 'package:pos_apotek/features/auth/data/user_repository.dart';
import 'package:pos_apotek/features/backup/data/backup_service.dart';
import 'package:pos_apotek/features/backup/presentation/backup_screen.dart';
import 'package:pos_apotek/features/products/data/photo_store.dart';
import 'package:pos_apotek/features/products/data/product_models.dart';
import 'package:pos_apotek/features/products/data/product_repository.dart';
import 'package:pos_apotek/features/settings/data/settings_repository.dart';
import 'package:pos_apotek/features/setup/data/setup_service.dart';

import 'helpers.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late Directory root;
  late AppPaths paths;
  final clock = FakeClock(DateTime(2026, 11, 25, 9));

  setUp(() async {
    db = memoryDatabase();
    root = Directory.systemTemp.createTempSync('backup_flow_');
    paths = AppPaths(
      documents: Directory('${root.path}/docs')..createSync(),
      temp: Directory('${root.path}/tmp')..createSync(),
    );
    final settings = SettingsRepository(db, clock.call);
    final users = UserRepository(db, fastHasher, clock.call);
    await SetupService(
      db,
      settings,
      users,
      RecoveryCodeService(settings, users, fastHasher),
    ).complete(
      store: const StoreProfile(name: 'Apotek Uji'),
      ownerName: 'Sari',
      ownerPin: '482915',
    );
    await ProductRepository(db, clock.call).create(
      const ProductInput(
        name: 'Paracetamol',
        drugClass: DrugClass.bebas,
        units: [UnitInput(name: 'Tablet', multiplier: 1, sellPrice: 500)],
      ),
    );
  });

  tearDown(() => root.deleteSync(recursive: true));

  /// Memberi waktu operasi file sungguhan (di luar FakeAsync) untuk selesai.
  Future<void> settleIo(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      // pump biasa: indikator loading berputar terus selama IO berjalan.
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('pemilik diingatkan backup; cadangan harian dibuat otomatis', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          pinHasherProvider.overrideWithValue(fastHasher),
          clockProvider.overrideWithValue(clock.call),
          photoStoreProvider.overrideWith((ref) => PhotoStore(paths.photos)),
          appPathsProvider.overrideWith((ref) async => paths),
        ],
        child: const PosApotekApp(),
      ),
    );
    await tester.pumpAndSettle();
    // Hanya satu pengguna → langsung ke PIN.
    for (final d in '482915'.split('')) {
      await tester.tap(find.text(d));
      await tester.pump();
    }
    await settleIo(tester);

    expect(find.text('Data belum pernah di-backup'), findsOneWidget);
    expect(
      paths.backups.listSync().where((f) => f.path.contains('harian_')),
      hasLength(1),
    );

    await tester.tap(find.byKey(const Key('backup-reminder')));
    await settleIo(tester);
    expect(find.text('Backup & Pulihkan'), findsOneWidget);
    expect(find.text('Belum pernah backup ke luar HP'), findsOneWidget);
    expect(find.text('Otomatis harian'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await db.close();
  });

  test('pengingat & teks waktu', () {
    final now = DateTime(2026, 11, 25, 9);
    expect(isExportDue(const BackupState(), now), isTrue);
    expect(
      isExportDue(BackupState(lastExportAt: DateTime(2026, 11, 20)), now),
      isFalse,
    );
    expect(
      isExportDue(BackupState(lastExportAt: DateTime(2026, 11, 18, 9)), now),
      isTrue,
    );
    expect(daysAgo(DateTime(2026, 11, 25, 1), now), 'hari ini');
    expect(daysAgo(DateTime(2026, 11, 24, 23), now), 'kemarin');
    expect(daysAgo(DateTime(2026, 11, 20), now), '5 hari lalu');
  });
}
