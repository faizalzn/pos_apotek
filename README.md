# POS Apotek

Aplikasi kasir (Point of Sale) untuk apotek kecil, dibuat dengan Flutter untuk HP dan tablet Android.
Dirancang **offline-first** dan **mudah dipakai oleh orang awam**.

> Status: **langkah 1 (fondasi) selesai** — setup awal, login PIN, pengguna. Belum siap dipakai berjualan.

## Fitur (Tahap 1)

- Manajemen produk: foto, satuan bertingkat (box/strip/tablet), harga beli & jual, golongan obat
- Stok per **batch & tanggal kedaluwarsa** (FEFO: yang ED-nya paling dekat keluar duluan)
- Peringatan stok menipis & obat mendekati ED
- Kasir: cari cepat, scan barcode (kamera / scanner USB-Bluetooth), hitung kembalian otomatis
- Pembayaran tunai & **QRIS dinamis** (dari QRIS statis milik merchant, tanpa payment gateway)
- Cetak struk ke printer thermal ESC/POS (Bluetooth / USB / WiFi), cadangan PDF/gambar
- Kirim struk via WhatsApp (satu ketukan)
- Login PIN dengan peran **Pemilik** & **Kasir**, buka/tutup shift
- Laporan harian & per shift
- Notifikasi Telegram ke pemilik (per transaksi & ringkasan tutup shift)
- Impor produk dari Excel/CSV dengan pencocokan kolom otomatis
- Backup & restore

Rencana lengkap: [docs/ROADMAP.md](docs/ROADMAP.md)

## Teknologi

| Kebutuhan | Pilihan |
|---|---|
| Framework | Flutter (target Android) |
| Database lokal | Drift (SQLite) |
| State management | Riverpod |

Alasan di balik setiap keputusan ada di [docs/decisions/](docs/decisions/).

## Setup pengembangan

1. Install [Flutter](https://docs.flutter.dev/get-started/install).
2. Salin file rahasia dan isi nilainya:
   ```bash
   cp secrets.example.json secrets.json
   ```
   `secrets.json` sudah masuk `.gitignore` — **jangan pernah di-commit**.
3. Jalankan:
   ```bash
   flutter pub get
   flutter run --dart-define-from-file=secrets.json
   ```

### Membuat bot Telegram (sekali saja)

1. Buka [@BotFather](https://t.me/BotFather) di Telegram, kirim `/newbot`, ikuti langkahnya.
2. Salin token & username bot ke `secrets.json`.

Pemilik apotek **tidak perlu** menyentuh token — cukup tekan tombol "Hubungkan" di aplikasi.

### Pengujian

```bash
flutter test
```

### Build APK

```bash
flutter build apk --release --dart-define-from-file=secrets.json
```

## Data privat

Repo ini publik, sehingga **tidak boleh** berisi: token, keystore, data apotek (nama, QRIS),
data pelanggan, file backup, atau file Excel asli. Semua itu diisi saat aplikasi berjalan
dan sudah dikecualikan lewat `.gitignore`. Untuk contoh data gunakan folder `sample_data/`
yang berisi data dummy saja.

## Dokumentasi

- [Arsitektur](docs/ARCHITECTURE.md)
- [Database](docs/DATABASE.md)
- [Roadmap](docs/ROADMAP.md)
- [Catatan keputusan (ADR)](docs/decisions/)
- [Changelog](CHANGELOG.md)
