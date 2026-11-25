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

/// Golongan obat sesuai penandaan di kemasan.
enum DrugClass {
  /// Lingkaran hijau.
  bebas,

  /// Lingkaran biru.
  bebasTerbatas,

  /// Lingkaran merah huruf K — perlu resep dokter.
  keras,

  /// Narkotika / psikotropika — perlu resep dan pencatatan khusus.
  narkotikaPsikotropika,

  /// Bukan obat: alat kesehatan, suplemen, kosmetik, dll.
  nonObat;

  String get label => switch (this) {
        DrugClass.bebas => 'Obat Bebas',
        DrugClass.bebasTerbatas => 'Obat Bebas Terbatas',
        DrugClass.keras => 'Obat Keras',
        DrugClass.narkotikaPsikotropika => 'Narkotika / Psikotropika',
        DrugClass.nonObat => 'Non-obat',
      };

  bool get requiresPrescription =>
      this == DrugClass.keras || this == DrugClass.narkotikaPsikotropika;
}

/// Produk yang dijual (obat maupun non-obat).
///
/// Stok tidak disimpan di sini, melainkan dijumlahkan dari [Batches] dalam
/// satuan terkecil (ADR-0007).
@DataClassName('Product')
class Products extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 120)();

  /// Kandungan / nama generik, mis. "Paracetamol 500 mg". Ikut dicari.
  TextColumn get genericName => text().withDefault(const Constant(''))();
  TextColumn get category => text().withDefault(const Constant(''))();
  TextColumn get drugClass => textEnum<DrugClass>()();

  /// Nama file foto di folder foto produk (bukan path lengkap).
  TextColumn get photoFile => text().nullable()();

  /// Batas stok menipis, dalam satuan terkecil. 0 = tidak diperingatkan.
  IntColumn get minStock => integer().withDefault(const Constant(0))();

  /// Produk yang diarsipkan tidak tampil di kasir, tetapi riwayatnya tetap ada.
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Satuan jual sebuah produk, mis. Tablet (1), Strip (10), Box (100).
@DataClassName('ProductUnit')
class ProductUnits extends Table {
  TextColumn get id => text()();
  TextColumn get productId => text().references(Products, #id)();
  TextColumn get name => text().withLength(min: 1, max: 30)();

  /// Isi satuan ini dalam satuan terkecil. Satuan terkecil = 1.
  IntColumn get multiplier => integer()();

  /// Harga jual dalam rupiah.
  IntColumn get sellPrice => integer()();
  TextColumn get barcode => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Satu kali penerimaan stok dengan nomor batch & tanggal kedaluwarsa sendiri.
@DataClassName('StockBatch')
class Batches extends Table {
  TextColumn get id => text()();
  TextColumn get productId => text().references(Products, #id)();
  TextColumn get batchNumber => text().withDefault(const Constant(''))();

  /// Tanggal kedaluwarsa. Kosong untuk barang tanpa ED.
  DateTimeColumn get expiryDate => dateTime().nullable()();

  /// Sisa stok batch ini, dalam satuan terkecil.
  IntColumn get quantity => integer()();

  /// Harga beli per satuan terkecil (rupiah, boleh pecahan).
  RealColumn get costPerUnit => real().withDefault(const Constant(0))();
  DateTimeColumn get receivedAt => dateTime()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Jenis perubahan stok.
enum StockMovementType {
  stockIn,
  sale,
  adjustment,
  disposal;

  String get label => switch (this) {
        StockMovementType.stockIn => 'Stok masuk',
        StockMovementType.sale => 'Terjual',
        StockMovementType.adjustment => 'Koreksi stok',
        StockMovementType.disposal => 'Dibuang (ED/rusak)',
      };
}

/// Catatan setiap perubahan stok, untuk penelusuran.
@DataClassName('StockMovement')
class StockMovements extends Table {
  TextColumn get id => text()();
  TextColumn get productId => text().references(Products, #id)();
  TextColumn get batchId => text().references(Batches, #id)();
  TextColumn get type => textEnum<StockMovementType>()();

  /// Perubahan dalam satuan terkecil: positif masuk, negatif keluar.
  IntColumn get quantity => integer()();
  TextColumn get note => text().withDefault(const Constant(''))();
  TextColumn get userId => text().nullable().references(Users, #id)();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
