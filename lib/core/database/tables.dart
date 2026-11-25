import 'package:drift/drift.dart';

/// Peran pengguna aplikasi.
///
/// - [owner] (Pemilik): akses penuh, termasuk laba, harga, dan pengguna.
/// - [cashier] (Kasir): hanya berjualan dan melihat stok.
enum UserRole {
  owner,
  cashier;

  String get label => switch (this) {
        UserRole.owner => 'Pemilik',
        UserRole.cashier => 'Kasir',
      };
}

/// Pengguna yang bisa masuk ke aplikasi dengan PIN.
///
/// Semua ID memakai UUID dan setiap baris memiliki `updated_at` agar siap
/// disinkronkan ke cloud kelak (ADR-0001).
@DataClassName('AppUser')
class Users extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 50)();
  TextColumn get role => textEnum<UserRole>()();

  /// Hash PBKDF2-HMAC-SHA256 dari PIN (base64). PIN tidak pernah disimpan.
  TextColumn get pinHash => text()();
  TextColumn get pinSalt => text()();

  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  /// Jumlah salah PIN berturut-turut; direset saat berhasil masuk.
  IntColumn get failedAttempts => integer().withDefault(const Constant(0))();

  /// Jika diisi dan masih di masa depan, pengguna tidak bisa mencoba PIN.
  DateTimeColumn get lockedUntil => dateTime().nullable()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Pengaturan aplikasi dalam bentuk key–value (nama apotek, alamat, dll.).
@DataClassName('AppSetting')
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {key};
}
