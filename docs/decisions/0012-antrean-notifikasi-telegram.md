# ADR-0012: Antrean notifikasi Telegram (outbox)

- **Status:** Diterima
- **Tanggal:** 2026-11-26

## Konteks

ADR-0003 memutuskan pemantauan lewat bot Telegram. Internet di apotek desa sering
putus. Pemilik ingin setiap transaksi tercatat di Telegram supaya tidak ada yang
terlewat, dan HP kasir belum tentu milik Pemilik.

## Keputusan

- **Outbox di database** (tabel `telegram_outbox`, skema v5).
  - Pesan ditulis di dalam transaksi database yang sama dengan penjualan, pembatalan,
    atau tutup shift. Kalau transaksinya tersimpan, pesannya pasti ikut tersimpan.
  - Baris dihapus setelah Telegram menerima pesan.
- **Pengirim latar** berjalan selama aplikasi terbuka:
  - Mengirim saat ada pesan baru dan setiap menit.
  - Urutan pesan dijaga (paling lama lebih dulu).
  - Saat offline, pengiriman berhenti dan dicoba lagi nanti.
  - HTTP 429 dihormati (`retry_after`).
  - Pesan yang ditolak permanen (HTTP 400) dibuang setelah 3 kali gagal, supaya tidak
    menahan antrean.
  - Pesan yang tertunda lebih dari 10 menit diberi keterangan "(tertunda)".
- **Isi pesan**:
  - Setiap transaksi: barang, total, cara bayar, dan peringatan stok.
  - Pembatalan: siapa, kapan, dan alasannya.
  - Tutup shift: rekonsiliasi kas.
  - Ringkasan harian.
  - File backup (tanpa foto) setelah tutup shift.
  - Setiap jenis bisa dimatikan.
- **Peringatan stok** hanya dikirim saat produk *baru* menjadi menipis atau habis, supaya
  tidak berulang di setiap penjualan.
- **Ringkasan harian** diantrekan saat aplikasi berjalan setelah hari berganti, untuk
  hari-hari yang belum terkirim (paling banyak 7 hari ke belakang). Tidak ada jadwal
  latar Android, karena aplikasi kasir umumnya terbuka setiap hari.
- **Menghubungkan dari HP mana pun**:
  - Tautan `t.me/<bot>?start=<kode>` bisa dibuka di HP ini, atau dikirim (mis. lewat
    WhatsApp) ke HP Pemilik.
  - Aplikasi menunggu `/start <kode>` lewat `getUpdates` (long polling) dan menyimpan
    `chat_id`.

- **Token bot diisi Pemilik di aplikasi** (Pengaturan → Notifikasi Telegram)
  (revisi 2026-11-26, menggantikan sebagian ADR-0003):
  - Token diperiksa dengan `getMe`, dan username bot diambil otomatis.
  - Token disimpan di `app_settings` (`telegram.bot_token`).
  - Token dari `secrets.json` saat build tetap didukung sebagai cadangan. Isian di
    aplikasi lebih diutamakan.
  - Mengganti bot memutus sambungan lama dan mengosongkan antrean.
  - Alasannya: Pemilik atau developer tidak perlu build ulang, dan token tidak
    tertanam di APK.

## Alternatif yang ditolak

- **Kirim langsung tanpa antrean:** pesan hilang saat offline.
- **WorkManager / layanan latar Android:** menambah izin dan kerumitan. Aplikasi kasir
  terbuka sepanjang jam buka.
- **Server perantara:** butuh biaya dan perawatan (Tahap 3).

## Konsekuensi

- Pesan baru terkirim saat aplikasi terbuka dan ada internet.
- Bila aplikasi dipulihkan dari backup, pesan yang belum terkirim di backup itu ikut
  terkirim.
- Token bot ikut tersimpan di file backup. Backup hanya boleh dibagikan ke tempat
  milik Pemilik. Kalau token bocor, buat token baru dengan `/revoke` di @BotFather.
