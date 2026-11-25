# ADR-0003: Pemantauan pemilik via notifikasi Telegram

- **Status:** Diterima
- **Tanggal:** 2026-11-25

## Konteks

Pemilik bergantian shift dengan pekerja dan ingin memantau penjualan dari HP pribadi
saat tidak berada di apotek. Dua perangkat di lokasi berbeda tidak bisa terhubung
langsung tanpa perantara di internet.

Pilihan yang dipertimbangkan:

- **A. Notifikasi Telegram** — gratis, cepat dibuat, tanpa server sendiri.
- **B. Sinkronisasi cloud** (Supabase/Firebase) — data penuh di kedua HP, lebih lama dibuat.

## Keputusan

Gunakan **A** di Tahap 1. Opsi B dipakai jika memang dibutuhkan (Tahap 3).

- Notifikasi **per transaksi** dan **ringkasan tutup shift**, masing-masing bisa diaktifkan/dimatikan.
- Token bot **ditanam di aplikasi** (lewat `--dart-define-from-file`, lihat ADR-0008).
- Pemilik tidak memasukkan token: tombol "Hubungkan" membuka bot dengan *deep link*
  `t.me/<bot>?start=<kode-unik>`, pemilik menekan Start, aplikasi mencocokkan kode
  lewat `getUpdates` dan menyimpan `chat_id`.
- Pesan yang gagal terkirim (offline) diantrekan dan dikirim ulang saat online.

## Konsekuensi

- Pemilik harus memakai Telegram.
- Token tertanam di APK bisa diekstrak; dapat diterima untuk satu apotek, **tidak** untuk
  rilis Play Store multi-apotek (perlu server perantara).
- `getUpdates` hanya mendukung satu konsumen per bot — cukup untuk satu apotek.
