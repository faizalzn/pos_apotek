# ADR-0011: Shift & rekonsiliasi kas laci

- **Status:** Diterima
- **Tanggal:** 2026-11-25

## Konteks

Pemilik berganti jaga dengan pegawai (pagi/sore) di HP yang sama dan ingin tahu
apakah uang di laci sesuai penjualan. Pengguna bukan orang teknis. Aturan shift
tidak boleh menghambat penjualan.

## Keputusan

- **Satu laci = satu shift terbuka.**
  - Kasir wajib membuka shift (mengisi modal awal) sebelum berjualan.
  - Saran modal awal diambil dari hitungan saat shift terakhir ditutup.
- **Transaksi masuk ke shift yang terbuka, siapa pun yang login.**
  - Pemilik yang ikut melayani tidak perlu membuka shift sendiri.
  - `sales.cashier_id` tetap mencatat siapa yang melayani.
- **Serah terima = tutup shift lalu buka shift baru.**
  - Shift boleh ditutup oleh pengguna lain; tercatat siapa yang menutup.
  - Saat logout dengan shift sendiri masih terbuka, aplikasi menawarkan untuk
    menutupnya. Kasir tetap boleh "keluar saja", misalnya untuk istirahat.
- **Kas masuk/keluar** dengan keterangan wajib, supaya pengeluaran kecil (galon,
  parkir) tidak menjadi selisih. Kas keluar tidak boleh melebihi isi laci.
- **Tutup shift:**
  - Aplikasi menampilkan uang yang seharusnya ada, kasir mengisi hitungannya, dan
    selisihnya ditampilkan langsung.
  - Bila ada selisih, keterangan wajib diisi; tombol baru aktif setelah diisi.
  - `expected_cash` disimpan sebagai angka tetap.
- **Pembatalan transaksi dari shift sebelumnya** dihitung sebagai pengembalian di
  shift yang sedang berjalan, karena uangnya keluar dari laci saat itu.
- Ringkasan shift bisa **dicetak** di printer thermal sebagai arsip kertas, lengkap
  dengan tempat paraf.

## Alternatif yang ditolak

- **Shift per pengguna (beberapa shift terbuka sekaligus):** membingungkan untuk
  satu laci dan satu HP.
- **Mengunci aplikasi sampai shift ditutup saat logout:** mengganggu bila pegawai
  hanya istirahat sebentar.
- **Hitung per pecahan uang:** menambah langkah. Bisa ditambahkan nanti bila
  diminta.

## Konsekuensi

- Ringkasan tutup shift menjadi dasar notifikasi Telegram "tutup shift" (langkah
  berikutnya).
- Transaksi sebelum v4 tidak punya shift. Pembatalannya tetap dihitung sebagai
  pengembalian di shift yang berjalan.
