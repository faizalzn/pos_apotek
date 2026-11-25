# Roadmap

## Tahap 1 — Siap dipakai di apotek

Urutan pengerjaan:

1. ✅ **Fondasi** — database, login PIN (Pemilik/Kasir), wizard setup awal
2. **Produk** — CRUD produk, foto, satuan bertingkat, tambah stok (batch + ED)
3. **Kasir** — cari/scan, keranjang, pembayaran tunai, kembalian
4. **QRIS dinamis** — scan QRIS statis merchant, sisipkan nominal
5. **Struk** — printer ESC/POS (Bluetooth/USB/WiFi), PDF/gambar, kirim via WhatsApp
6. **Shift & laporan** — buka/tutup shift, selisih kas, laporan harian & per shift
7. **Notifikasi Telegram** — per transaksi & ringkasan tutup shift
8. **Impor & backup** — impor Excel/CSV dengan pemetaan kolom, backup/restore

Setelah langkah 3 aplikasi sudah bisa diuji coba di apotek.

## Tahap 2

- Batch & FEFO lengkap, laporan ED
- Pembelian dari supplier (stok masuk terstruktur)
- Laporan laba
- Cetak label QR/barcode untuk produk tanpa barcode
- User manual bergambar (di dalam aplikasi + PDF)

## Tahap 3

- Sinkronisasi cloud (Supabase/Firebase) & multi-perangkat
- Payment gateway dengan konfirmasi otomatis
- Bot Telegram melalui server (tidak ditanam di aplikasi)
- Rilis ke Play Store
