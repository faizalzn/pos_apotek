# ADR-0009: Kode darurat developer (Ed25519 challenge–response)

- **Status:** Diterima
- **Tanggal:** 2026-11-25

## Konteks

Jika Pemilik satu-satunya lupa PIN **dan** kehilangan kode pemulihan, akun Pemilik
terkunci permanen: satu-satunya jalan adalah instal ulang dan kehilangan data.
Pengguna bukan orang teknis, dan fitur pemulihan tidak boleh mengganggu pekerjaan
sehari-hari.

## Keputusan

Tiga lapis pemulihan, dari yang paling mudah:

1. **Pemilik kedua** dapat mengatur ulang PIN — dianjurkan di wizard dan di layar Pengguna.
2. **Kode pemulihan** yang dicatat di kertas (ADR terkait: fondasi).
3. **Kode darurat developer** (jalan terakhir):
   - Aplikasi membuat kode tantangan acak `ABCD-EFGH` (berlaku 24 jam, tetap sama
     meski aplikasi ditutup).
   - Developer menandatangani `POSAPOTEK-RESCUE-v1:<tantangan>` dengan kunci privat
     **Ed25519** memakai `tool/kode_darurat.dart`.
   - Aplikasi memeriksa tanda tangan dengan **kunci publik** yang disisipkan saat build
     (`RESCUE_PUBLIC_KEY`, ADR-0008). Berhasil → Pemilik membuat PIN baru, kode tantangan
     hangus, kode pemulihan baru dibuat.
   - Kode balasan (86 karakter) dikirim lewat WhatsApp dan **ditempel**, bukan diketik.
     Aplikasi mengambil kode dari seluruh teks pesan yang ditempel.

Alternatif yang ditolak:

- **Kode rahasia bersama (HMAC) yang pendek** — mudah diketik, tetapi rahasianya ada di
  APK sehingga siapa pun yang membongkar aplikasi bisa membuat kode sendiri.
- **Kode master tetap** — sekali bocor, semua instalasi terbuka selamanya.

## Konsekuensi

- Tidak ada langkah tambahan dalam pemakaian sehari-hari; layar ini hanya muncul dari
  "Lupa PIN? → Kode pemulihan hilang?".
- Developer wajib menjaga kunci privat (password manager). Jika hilang, instalasi lama
  tidak bisa dipulihkan dengan cara ini.
- Bila `RESCUE_PUBLIC_KEY` kosong, layar bantuan hanya menampilkan petunjuk.
- Untuk rilis Play Store multi-apotek, alur ini perlu ditinjau ulang (developer tidak
  seharusnya bisa membuka akun semua apotek).
