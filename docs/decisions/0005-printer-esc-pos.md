# ADR-0005: Dukungan printer lewat standar ESC/POS

- **Status:** Diterima
- **Tanggal:** 2026-11-25

## Konteks

Jenis printer yang akan dipakai belum diketahui. Hampir semua printer thermal murah
di Indonesia (EPPOS, Panda, Xprinter, Iware, dll.) memakai perintah ESC/POS.

## Keputusan

- Struk dibangkitkan sebagai perintah **ESC/POS**.
- Koneksi: **Bluetooth**, **USB (OTG)**, dan **WiFi/LAN**.
- Lebar kertas **58mm / 80mm** dapat dipilih di pengaturan; ada tombol "Tes Cetak".
- Cadangan: struk dapat dibagikan sebagai **PDF/gambar**.

## Konsekuensi

- Mendukung sebagian besar printer di pasaran tanpa kode khusus per merek.
- Printer "mini/cat printer" yang hanya bekerja dengan aplikasi bawaannya **tidak didukung**.
- Rekomendasi pembelian: printer berlabel "ESC/POS" dan "support Android", 58mm.
