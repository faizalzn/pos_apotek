# Roadmap

## Tahap 1 — Siap dipakai di apotek

Urutan pengerjaan:

1. ✅ **Fondasi** — database, login PIN (Pemilik/Kasir), wizard setup awal
   - ✅ Kode darurat developer & saran Pemilik kedua
2. ✅ **Produk** — CRUD produk, foto, satuan bertingkat, tambah stok (batch + ED)
3. ✅ **Kasir** — cari/scan, keranjang, diskon, tunai/QRIS manual, riwayat & pembatalan
3b. ✅ **Backup & restore** — kirim ke Drive/WhatsApp, cadangan harian, pemulihan (juga dari wizard)
4. ✅ **Struk** (dimajukan) — printer thermal ESC/POS Bluetooth & WiFi, layanan cetak
   Android, PDF/gambar, WhatsApp, logo apotek
5. **Shift & laporan** — buka/tutup shift, selisih kas, laporan harian & per shift
6. **Notifikasi Telegram** — setiap transaksi & pembatalan (antrean offline), ringkasan
   tutup shift & harian, kirim backup otomatis
7. **QRIS dinamis** — scan QRIS statis merchant, sisipkan nominal
8. **Impor** — impor Excel/CSV dengan pemetaan kolom
9. Printer thermal **USB (OTG)** — bila nanti printer yang dipakai berjenis USB

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
