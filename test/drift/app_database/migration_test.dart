// dart format width=80
// ignore_for_file: unused_local_variable, unused_import
import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:pos_apotek/core/database/app_database.dart';
import 'package:flutter_test/flutter_test.dart';

import 'generated/schema.dart';

import 'generated/schema_v1.dart' as v1;
import 'generated/schema_v2.dart' as v2;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  group('simple database migrations', () {
    // These simple tests verify all possible schema updates with a simple (no
    // data) migration. This is a quick way to ensure that written database
    // migrations properly alter the schema.
    const versions = GeneratedHelper.versions;
    for (final (i, fromVersion) in versions.indexed) {
      group('from $fromVersion', () {
        for (final toVersion in versions.skip(i + 1)) {
          test('to $toVersion', () async {
            final schema = await verifier.schemaAt(fromVersion);
            final db = AppDatabase(schema.newConnection());
            await verifier.migrateAndValidate(db, toVersion);
            await db.close();
          });
        }
      });
    }
  });

  // Memastikan data dari versi lama tetap utuh setelah migrasi.
  test('migration from v1 to v2 does not corrupt data', () async {
    const ts = '2026-11-25T08:00:00.000';
    final oldUsersData = <v1.UsersData>[
      const v1.UsersData(
        id: 'u1',
        name: 'Pemilik',
        role: 'owner',
        pinHash: 'hash',
        pinSalt: 'salt',
        isActive: 1,
        failedAttempts: 2,
        lockedUntil: null,
        createdAt: ts,
        updatedAt: ts,
      ),
    ];
    final expectedNewUsersData = <v2.UsersData>[
      const v2.UsersData(
        id: 'u1',
        name: 'Pemilik',
        role: 'owner',
        pinHash: 'hash',
        pinSalt: 'salt',
        isActive: 1,
        failedAttempts: 2,
        lockedUntil: null,
        createdAt: ts,
        updatedAt: ts,
      ),
    ];

    final oldAppSettingsData = <v1.AppSettingsData>[
      const v1.AppSettingsData(
        key: 'store.name',
        value: 'Apotek Uji',
        updatedAt: ts,
      ),
    ];
    final expectedNewAppSettingsData = <v2.AppSettingsData>[
      const v2.AppSettingsData(
        key: 'store.name',
        value: 'Apotek Uji',
        updatedAt: ts,
      ),
    ];

    await verifier.testWithDataIntegrity(
      oldVersion: 1,
      newVersion: 2,
      createOld: v1.DatabaseAtV1.new,
      createNew: v2.DatabaseAtV2.new,
      openTestedDatabase: AppDatabase.new,
      createItems: (batch, oldDb) {
        batch.insertAll(oldDb.users, oldUsersData);
        batch.insertAll(oldDb.appSettings, oldAppSettingsData);
      },
      validateItems: (newDb) async {
        expect(expectedNewUsersData, await newDb.select(newDb.users).get());
        expect(
          expectedNewAppSettingsData,
          await newDb.select(newDb.appSettings).get(),
        );
      },
    );
  });
}
