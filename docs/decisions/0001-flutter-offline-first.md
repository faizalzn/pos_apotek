# ADR-0001: Flutter + database lokal (offline-first)

- **Status:** Diterima
- **Tanggal:** 2026-11-25

## Konteks

Apotek berada di desa dengan koneksi internet yang tidak stabil dan sudah beroperasi,
sehingga aplikasi harus cepat jadi. Perangkat kasir berupa HP atau tablet Android.
Di masa depan aplikasi ingin dirilis ke Play Store.

## Keputusan

- **Flutter** sebagai framework (satu kode untuk Android, iOS bisa menyusul).
- **Drift (SQLite)** sebagai database lokal; semua transaksi berjalan tanpa internet.
- **Riverpod** untuk state management.
- Semua ID memakai **UUID** dan setiap tabel memiliki kolom `updated_at`, agar nanti
  bisa disinkronkan ke cloud (Supabase/Firebase) tanpa migrasi besar.

## Konsekuensi

- Kasir tetap bisa berjualan saat internet mati.
- Tidak ada biaya server di Tahap 1.
- Data hanya ada di satu perangkat → fitur **backup/restore wajib** ada.
- Pemantauan jarak jauh tidak real-time penuh (lihat ADR-0003).
