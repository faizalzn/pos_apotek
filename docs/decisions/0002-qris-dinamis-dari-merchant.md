# ADR-0002: QRIS dinamis dari QRIS statis merchant

- **Status:** Diterima
- **Tanggal:** 2026-11-25

## Konteks

Pelanggan sebaiknya cukup scan QR dan nominal langsung terisi. Payment gateway
(Xendit, Midtrans, dll.) memerlukan pendaftaran, dokumen usaha, dan memotong fee
per transaksi.

## Keputusan

Aplikasi membaca payload QRIS statis milik merchant (dengan scan stiker QRIS via kamera),
lalu membuat QRIS dinamis secara offline:

1. Mengubah *Point of Initiation Method* (tag `01`) dari `11` (statis) menjadi `12` (dinamis).
2. Menyisipkan nominal transaksi (tag `54`).
3. Menghitung ulang checksum CRC16-CCITT (tag `63`).

### Implementasi (2026-11-26)

- **Sumber QRIS apotek** (Pengaturan → QRIS apotek, khusus Pemilik):
  - scan stiker dengan kamera,
  - ambil dari gambar atau screenshot QRIS, atau
  - tempel teks QRIS.
- **Pemeriksaan saat disimpan:**
  - Diawali `000201`.
  - Format TLV benar.
  - CRC tag `63` cocok.
  - Ada merchant `ID.CO.QRIS` di tag 26–51.
  - Negara `ID` dan mata uang `360`.
- **Disimpan** sebagai pengaturan `qris.payload`. Ini data privat yang tidak boleh
  masuk repo (ADR-0008), tapi ikut masuk backup.
- **Membuat QR bernominal:**
  - Tag `54` disisipkan sesuai urutan tag.
  - Tag tip `55`–`57` dibuang, supaya pelanggan tidak diminta tip.
  - CRC16-CCITT-FALSE dihitung ulang.
  - QR dinamis pun bisa dipakai sebagai sumber (nominalnya diganti).
- **Uji coba Rp1** ditampilkan di layar pengaturan. Pemilik wajib men-scan sekali
  dengan aplikasi bank sebelum dipakai.
- **Di kasir:** QR bernominal tampil di layar pembayaran, plus tampilan layar penuh
  untuk pelanggan. Bila QRIS belum diatur, alur lama (stiker) tetap dipakai.
- **Verifikasi:** CRC dicek dengan vektor standar (`123456789` → `29B1`) dan
  `binascii.crc_hqx`. QR yang dirender juga sudah dibaca ulang dengan ZXing.

## Konsekuensi

- Gratis, tanpa pihak ketiga, tanpa pendaftaran tambahan. MDR resmi dari penerbit QRIS tetap berlaku.
- **Bukan fitur resmi** penerbit QRIS; perlu diuji dengan nominal kecil pada QRIS milik apotek.
- **Tidak ada konfirmasi pembayaran otomatis**: kasir mengecek notifikasi di aplikasi
  merchant/bank lalu menekan "Sudah dibayar".
- Konfirmasi otomatis hanya bisa lewat payment gateway (Tahap 3).
