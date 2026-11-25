# ADR-0004: Kirim struk via WhatsApp click-to-chat

- **Status:** Diterima
- **Tanggal:** 2026-11-25

## Konteks

Ingin bisa mengirim pesan/struk ke pelanggan setelah transaksi, sebagai fitur sampingan.

Pilihan yang dipertimbangkan:

1. **Click-to-chat** (`wa.me`) — membuka WhatsApp dengan pesan terisi; kasir menekan kirim.
2. **Gateway tidak resmi** (Fonnte, Wablas, dll.) — otomatis penuh, berbayar, risiko nomor diblokir.
3. **WhatsApp Business API resmi** — verifikasi Meta, bayar per pesan, template harus disetujui.

## Keputusan

Gunakan **opsi 1**, sebagai tombol kecil "Kirim via WA" di layar selesai transaksi.

## Konsekuensi

- Gratis dan tanpa risiko pemblokiran.
- Tidak sepenuhnya otomatis (butuh satu ketukan "kirim").
- Nomor HP pelanggan **opsional** dan hanya disimpan dengan persetujuan pelanggan (UU PDP).
- Opsi 2 bisa ditambahkan kelak sebagai pengaturan "Sambungkan WhatsApp".
