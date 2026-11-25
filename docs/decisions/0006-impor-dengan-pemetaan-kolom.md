# ADR-0006: Impor Excel/CSV dengan pemetaan kolom

- **Status:** Diterima
- **Tanggal:** 2026-11-25

## Konteks

Data produk awal mungkin sudah ada dalam Excel dengan format kolom yang tidak bisa
dipastikan. Pengguna bukan programmer.

## Keputusan

Alur impor:

1. Pilih file Excel (`.xlsx`) atau CSV.
2. Aplikasi **menebak kolom otomatis** dari judulnya (mis. "Nama Obat"/"Nama Barang"/"Produk" → Nama).
3. Layar **pencocokan kolom** dengan dropdown untuk mengoreksi tebakan.
4. **Pratinjau**: baris bermasalah ditandai merah (harga bukan angka, nama kosong, dll.).
5. Untuk produk yang sudah ada: pilih **perbarui** atau **lewati**.

Disediakan juga **template Excel** yang langsung cocok tanpa pemetaan.

## Konsekuensi

- Format apa pun bisa diimpor selama datanya berbentuk tabel.
- Perlu kamus sinonim judul kolom yang terus diperkaya.
