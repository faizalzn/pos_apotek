# Database

SQLite lokal melalui [Drift](https://drift.simonbinder.eu/). Definisi tabel ada di
[`lib/core/database/tables.dart`](../lib/core/database/tables.dart).

Konvensi (ADR-0001):

- Primary key berupa **UUID** (teks), agar data dari beberapa perangkat tidak bentrok
  saat sinkronisasi cloud kelak.
- Setiap tabel memiliki `updated_at`.
- Tanggal disimpan sebagai teks **ISO-8601** (lihat `build.yaml`).

Versi skema saat ini: **1**.

## Diagram

```mermaid
erDiagram
    users {
        TEXT id PK "UUID"
        TEXT name "unik di antara pengguna aktif"
        TEXT role "owner | cashier"
        TEXT pin_hash "PBKDF2-HMAC-SHA256, base64"
        TEXT pin_salt "16 byte acak, base64"
        BOOL is_active
        INT failed_attempts "salah PIN berturut-turut"
        TEXT locked_until "nullable"
        TEXT created_at
        TEXT updated_at
    }
    app_settings {
        TEXT key PK
        TEXT value
        TEXT updated_at
    }
```

Tabel produk, batch, transaksi, dan shift ditambahkan di langkah berikutnya
(lihat [ROADMAP](ROADMAP.md)).

## Kunci `app_settings`

| Kunci | Isi |
|---|---|
| `app.setup_completed` | `true` setelah wizard selesai |
| `store.name` | Nama apotek |
| `store.address` | Alamat |
| `store.phone` | Telepon / WhatsApp |
| `receipt.footer` | Catatan di bawah struk |
| `auth.recovery_hash` | Hash kode pemulihan Pemilik |
| `auth.recovery_salt` | Salt kode pemulihan |

## Migrasi

Setiap perubahan skema setelah aplikasi dipakai di apotek **wajib** menaikkan
`schemaVersion` di `AppDatabase` dan menambahkan langkah migrasi, agar data yang
sudah ada tidak hilang.
