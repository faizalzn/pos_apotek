# ADR-0005: Dukungan printer lewat standar ESC/POS

- **Status:** Diterima
- **Tanggal:** 2026-11-25

## Konteks

Jenis printer yang akan dipakai belum diketahui. Hampir semua printer thermal murah
di Indonesia (EPPOS, Panda, Xprinter, Iware, dll.) memakai perintah ESC/POS.

## Keputusan

- Satu tata letak struk (`buildReceipt` → daftar `ReceiptLine`) dipakai untuk tiga
  keluaran: perintah **ESC/POS**, **PDF** (huruf Courier, jadi sama persis dengan
  cetakan), dan **teks WhatsApp** (blok monospace).
- Hanya karakter ASCII yang dikirim ke printer. Karakter lain diganti
  (× → x, · → -), karena code page printer murah berbeda-beda.
- Koneksi:
  - **Bluetooth** klasik (SPP), lewat `print_bluetooth_thermal`; printer dipasangkan
    dulu di pengaturan Bluetooth HP.
  - **WiFi/LAN**: socket TCP langsung ke port 9100.
  - **Layanan cetak Android** (`printing`): PDF ke printer biasa yang punya plugin
    cetak.
  - **USB (OTG)** ditunda sampai ada printer USB untuk diuji. Printer kelas USB
    tidak memakai serial, jadi perlu plugin khusus.
- Logo: gambar hitam-putih (ambang 50%, transparan = putih), lebar 60% kertas,
  dikirim dengan `GS v 0` per potongan 64 baris agar printer dengan buffer kecil
  tidak macet.
- Lebar kertas **58 mm (32 kolom) / 80 mm (48 kolom)** dan tombol **Cetak tes** ada
  di pengaturan. Cetak otomatis setelah transaksi bisa dimatikan.
- Cetak ulang dari riwayat diberi tanda **SALINAN**, dan transaksi batal diberi
  tanda **DIBATALKAN**.
- Tanpa printer, struk tetap bisa dikirim lewat WhatsApp (`wa.me`) atau dibagikan
  sebagai gambar/PDF.

## Konsekuensi

- Mendukung sebagian besar printer di pasaran tanpa kode khusus per merek.
- Printer "mini/cat printer" yang hanya bekerja dengan aplikasi bawaannya **tidak didukung**.
- Rekomendasi pembelian: printer berlabel "ESC/POS" dan "support Android", 58mm.
