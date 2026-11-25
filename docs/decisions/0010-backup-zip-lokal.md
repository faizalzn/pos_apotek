# ADR-0010: Backup berupa file .zip, disimpan pengguna di luar HP

- **Status:** Diterima
- **Tanggal:** 2026-11-25

## Konteks

Semua data hanya ada di HP (ADR-0001). Bila HP hilang, rusak, atau aplikasi
terhapus, data penjualan dan stok ikut hilang. Belum ada server, dan pengguna bukan
orang teknis.

## Keputusan

- **Isi backup:** satu file `.zip`:
  - `manifest.json` (format, versi skema, waktu, nama apotek)
  - `pos_apotek.sqlite`, salinan dibuat dengan `VACUUM INTO` sehingga utuh walau
    aplikasi sedang dipakai
  - `product_photos/*`
- **Ke luar HP (perlindungan utama):** Pemilik menekan **Kirim backup** (lembar
  berbagi Android: Google Drive, WhatsApp ke nomor sendiri, email) atau **Simpan**
  (pemilih file: folder Download, flashdisk OTG).
- **Pengingat:** kartu merah di beranda Pemilik bila sudah 7 hari tidak ada backup
  ke luar HP. Catatan waktunya disimpan di `backups/state.json`, di luar database,
  supaya tetap benar setelah pemulihan.
- **Cadangan harian otomatis** di folder aplikasi:
  - hanya database (tanpa foto), 7 terakhir disimpan
  - melindungi dari salah ubah atau terhapus, bukan dari HP hilang
- **Pemulihan:**
  1. File dibongkar ke folder sementara lalu diperiksa: format, `PRAGMA
     integrity_check`, versi skema tidak lebih baru dari aplikasi, ada akun
     Pemilik aktif, nama foto aman.
  2. Pemilik melihat ringkasan (nama apotek, tanggal, jumlah produk dan transaksi)
     lalu mengonfirmasi.
  3. Data saat ini disimpan dulu sebagai cadangan "Sebelum pemulihan".
  4. Database ditutup, file diganti dengan `rename` (atomik), lalu aplikasi
     dimulai ulang (`AppRoot` membuat `ProviderContainer` baru). Backup dari versi
     lama dimigrasi otomatis saat dibuka.
- Pemulihan juga tersedia di **wizard setup** untuk pindah ke HP baru.

## Alternatif yang ditolak

- **Sinkronisasi cloud (Supabase/Firebase):** butuh akun, internet, dan biaya.
  Ditunda ke Tahap 3.
- **Backup otomatis ke Google Drive lewat API:** butuh login Google dan
  verifikasi OAuth di Play Store. Lembar berbagi Android sudah cukup.
- **Enkripsi file backup:** PIN disimpan sebagai hash PBKDF2, tidak ada data
  pelanggan, dan sandi tambahan berisiko lupa. Bisa ditambahkan nanti.

## Konsekuensi

- Pengguna tetap harus menekan tombol backup. Pengingat 7 hari mengurangi risiko
  lupa.
- Setelah notifikasi Telegram (langkah 7), backup bisa dikirim otomatis ke
  Telegram Pemilik setiap tutup shift.
