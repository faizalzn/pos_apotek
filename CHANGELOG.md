# Changelog

Format mengikuti [Keep a Changelog](https://keepachangelog.com/id-ID/1.1.0/).

## [Unreleased]

### Ditambahkan
- **Shift (langkah 5)**:
  - Buka shift dengan modal awal; Kasir meminta buka shift dulu sebelum berjualan.
  - Kas masuk/keluar dengan keterangan (mis. beli galon, setor ke Pemilik).
  - Tutup shift: uang seharusnya vs hitungan, selisih langsung tampil, keterangan
    wajib bila tidak pas. Ringkasan bisa dicetak.
  - Status shift di beranda; pengingat tutup shift saat keluar.
  - Pembatalan transaksi dari shift sebelumnya dihitung sebagai pengembalian.
- **Laporan (Pemilik)**: hari ini, kemarin, 7 hari, bulan ini/lalu, atau pilih tanggal.
  Omzet, laba kotor & margin, rata-rata, tunai vs QRIS, diskon, pembatalan, per hari,
  obat terlaris, per kasir, dan daftar shift beserta selisihnya.
- Database versi 4 (`shifts`, `cash_entries`, `sales.shift_id`) dengan migrasi otomatis.
- **Struk (langkah 4, dimajukan)**:
  - Setelah transaksi: **Cetak struk**, **WhatsApp** (ke nomor pelanggan atau pilih
    kontak), **Bagikan** sebagai gambar/PDF. Cetak otomatis bila printer sudah diatur.
  - Cetak ulang dari Riwayat (bertanda SALINAN).
  - Pengaturan → **Printer & struk**: printer thermal Bluetooth atau WiFi (ESC/POS),
    atau printer lain lewat layanan cetak Android; kertas 58/80 mm; cetak tes.
  - **Logo apotek** di Data apotek, tampil di struk & ikut backup.
- **Backup & pulihkan (langkah 3b)** — menu Pengaturan → Backup & pulihkan (Pemilik):
  - Kirim backup lengkap (data + foto) lewat Google Drive/WhatsApp, atau simpan ke
    penyimpanan HP/flashdisk.
  - Pengingat di beranda bila 7 hari belum backup ke luar HP.
  - Cadangan harian otomatis di HP (7 hari terakhir).
  - Pulihkan dari file atau dari cadangan otomatis; file diperiksa dulu, data saat ini
    disimpan sebagai cadangan, lalu aplikasi dibuka ulang.
  - Wizard setup: **Pulihkan dari backup** untuk pindah ke HP baru.
- **Kasir (langkah 3)**:
  - Cari barang atau scan barcode (kamera, atau scanner USB/Bluetooth yang mengetik
    lalu Enter). Produk dengan beberapa satuan → pilih satuan.
  - Keranjang: ubah jumlah, cek stok layak jual, peringatan **obat keras perlu resep**.
  - Di tablet daftar barang & keranjang tampil berdampingan.
  - Pemilik bisa mengubah harga dan memberi diskon per barang dan/atau diskon total
    (rupiah atau persen), keduanya opsional. Total tidak dibulatkan.
  - Pembayaran tunai (uang pas & pecahan cepat, kembalian) atau QRIS (konfirmasi manual).
  - Stok berkurang otomatis secara FEFO; harga beli tercatat untuk laporan laba.
  - Riwayat transaksi per hari dan detailnya; Pemilik bisa **membatalkan** transaksi
    (stok kembali ke batch asal).
- **Peringatan kedaluwarsa bisa diatur**: pengaturan umum (1–12 bulan, bawaan 3 bulan)
  dan pengaturan khusus per produk.
- Database versi 3 dengan migrasi otomatis dari versi 1 & 2.

### Diperbaiki
- Dialog berisi kolom isian bisa error saat ditutup (controller dibuang sebelum
  animasi selesai).

### Ditambahkan
- **Produk (langkah 2)**:
  - Tambah/ubah produk: foto (kamera/galeri), kandungan, kategori, golongan obat
    (dengan warna penanda seperti di kemasan), stok minimum.
  - Satuan bertingkat (mis. Tablet → Strip isi 10 → Box isi 100), harga & barcode
    per satuan, scan barcode dengan kamera.
  - Tambah stok per batch dengan ED (pilih bulan & tahun), harga beli opsional
    (hanya Pemilik), konversi otomatis ke satuan terkecil.
  - Stok FEFO: batch dengan ED terdekat dijual dulu, batch kedaluwarsa tidak dijual.
  - Koreksi stok (stock opname) & buang stok ED/rusak, dengan riwayat lengkap.
  - Daftar produk dengan pencarian (nama, kandungan, barcode) dan filter.
  - Menu **Stok & ED**: jumlah produk kedaluwarsa, hampir ED (≤ 3 bulan),
    stok menipis, dan habis.
  - Arsipkan produk tanpa menghapus riwayat.
- Database versi 2 dengan migrasi otomatis dari versi 1 (data lama tetap utuh) dan
  tes migrasi (`drift_dev make-migrations`).

### Ditambahkan
- **Kode darurat developer**: Pemilik yang lupa PIN dan kehilangan kode pemulihan bisa
  membuat PIN baru lewat kode tantangan → balasan dari developer (Ed25519), tanpa
  kehilangan data. Alat developer: `tool/kode_darurat.dart`. Panduan: `docs/KODE_DARURAT.md`.
- Saran membuat **Pemilik kedua** di akhir wizard dan di layar Pengguna.
- `secrets.example.json`: `RESCUE_PUBLIC_KEY`, `DEVELOPER_WHATSAPP`.

### Diperbaiki
- Mengembalikan dependency `material_ui`: sejak Flutter 3.47 ini adalah paket Material
  resmi, dan `package:flutter/material.dart` sudah deprecated.

### Ditambahkan
- **Fondasi (langkah 1)**:
  - Database lokal SQLite (Drift) dengan tabel `users` dan `app_settings`.
  - Wizard setup awal: data apotek, akun Pemilik + PIN, kode pemulihan.
  - Login dengan pilih nama + PIN 6 angka, penguncian bertahap setelah 5 kali salah.
  - Peran Pemilik & Kasir; menu Laporan hanya untuk Pemilik.
  - Lupa PIN: Pemilik memakai kode pemulihan, Kasir diatur ulang oleh Pemilik.
  - Pengaturan: data apotek, kelola pengguna, ganti PIN, buat kode pemulihan baru.
  - Beranda dengan menu kotak besar (fitur lain ditandai "Segera hadir").
- Dokumentasi teknis: `docs/ARCHITECTURE.md`, `docs/DATABASE.md`.
- Inisialisasi proyek Flutter (target Android & iOS).
- Dokumentasi awal: README, roadmap, catatan keputusan (ADR).
- `.gitignore` untuk data privat & rahasia, template `secrets.example.json`.
