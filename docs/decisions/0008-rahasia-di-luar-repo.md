# ADR-0008: Rahasia di luar repo, disisipkan saat build

- **Status:** Diterima
- **Tanggal:** 2026-11-25

## Konteks

Repo ini publik. Aplikasi membutuhkan token bot Telegram, dan menyimpan data apotek
serta pelanggan.

## Keputusan

- Rahasia disimpan di `secrets.json` (masuk `.gitignore`); repo hanya memuat `secrets.example.json` kosong.
- Rahasia disisipkan saat build: `flutter build apk --dart-define-from-file=secrets.json`.
- Data apotek (nama, alamat, logo, QRIS), pengguna, dan pelanggan **diisi saat runtime**
  dan hanya tersimpan di perangkat — tidak pernah di kode.
- Keystore, file backup, database, dan file Excel/CSV asli dikecualikan lewat `.gitignore`.
  Contoh data hanya boleh berupa data dummy di `sample_data/`.

## Konsekuensi

- Repo aman untuk publik.
- Developer baru harus membuat `secrets.json` sendiri sebelum build (dijelaskan di README).
