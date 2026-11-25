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

## Konsekuensi

- Gratis, tanpa pihak ketiga, tanpa pendaftaran tambahan. MDR resmi dari penerbit QRIS tetap berlaku.
- **Bukan fitur resmi** penerbit QRIS; perlu diuji dengan nominal kecil pada QRIS milik apotek.
- **Tidak ada konfirmasi pembayaran otomatis**: kasir mengecek notifikasi di aplikasi
  merchant/bank lalu menekan "Sudah dibayar".
- Konfirmasi otomatis hanya bisa lewat payment gateway (Tahap 3).
