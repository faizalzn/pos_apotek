# Changelog

Format mengikuti [Keep a Changelog](https://keepachangelog.com/id-ID/1.1.0/).

## [Unreleased]

### Ditambahkan
- **Kode darurat developer**: Pemilik yang lupa PIN dan kehilangan kode pemulihan bisa
  membuat PIN baru lewat kode tantangan → balasan dari developer (Ed25519), tanpa
  kehilangan data. Alat developer: `tool/kode_darurat.dart`. Panduan: `docs/KODE_DARURAT.md`.
- Saran membuat **Pemilik kedua** di akhir wizard dan di layar Pengguna.
- `secrets.example.json`: `RESCUE_PUBLIC_KEY`, `DEVELOPER_WHATSAPP`.

### Diperbaiki
- Mengembalikan dependency `material_ui`: sejak Flutter 3.47 ini adalah paket Material
  resmi, dan `package:flutter/material.dart` sudah deprecated.

### Ditambahkan
- **Fondasi (langkah 1)**:
  - Database lokal SQLite (Drift) dengan tabel `users` dan `app_settings`.
  - Wizard setup awal: data apotek, akun Pemilik + PIN, kode pemulihan.
  - Login dengan pilih nama + PIN 6 angka, penguncian bertahap setelah 5 kali salah.
  - Peran Pemilik & Kasir; menu Laporan hanya untuk Pemilik.
  - Lupa PIN: Pemilik memakai kode pemulihan, Kasir diatur ulang oleh Pemilik.
  - Pengaturan: data apotek, kelola pengguna, ganti PIN, buat kode pemulihan baru.
  - Beranda dengan menu kotak besar (fitur lain ditandai "Segera hadir").
- Dokumentasi teknis: `docs/ARCHITECTURE.md`, `docs/DATABASE.md`.
- Inisialisasi proyek Flutter (target Android & iOS).
- Dokumentasi awal: README, roadmap, catatan keputusan (ADR).
- `.gitignore` untuk data privat & rahasia, template `secrets.example.json`.
