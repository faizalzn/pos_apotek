# Panduan Kode Darurat (untuk developer)

Kode darurat adalah **jalan terakhir** bila Pemilik lupa PIN **dan** kehilangan kode
pemulihan, serta tidak ada Pemilik lain yang bisa mengatur ulang PIN-nya.
Data apotek tetap utuh. Alasan desainnya ada di
[ADR-0009](decisions/0009-kode-darurat-developer.md).

Yang dibutuhkan hanya laptop dengan Flutter (sudah termasuk Dart) dan folder proyek ini.

---

## A. Persiapan (sekali saja, sebelum build untuk apotek)

### 1. Buat kunci

```bash
dart run tool/kode_darurat.dart siapkan
```

Keluarannya kira-kira:

```
✅ Kunci darurat berhasil dibuat.

1) Kunci PRIVAT tersimpan di:
   /home/<anda>/.config/pos_apotek/kunci_darurat_privat.txt
   ...
2) Salin baris berikut ke secrets.json:
   "RESCUE_PUBLIC_KEY": "q3J0...=",
```

Ada **dua kunci**:

| | Kunci **privat** | Kunci **publik** |
|---|---|---|
| Fungsi | Membuat kode balasan | Memeriksa kode balasan |
| Disimpan di | Laptop Anda (di luar folder proyek) | Di dalam aplikasi |
| Rahasia? | **Ya, sangat.** Siapa pun yang memegangnya bisa membuka akun Pemilik | Tidak, aman diketahui orang |

### 2. Simpan cadangan kunci privat

Buka file kunci privat, salin isinya (satu baris), lalu simpan di **password manager**
(Bitwarden, 1Password, Google Password Manager, dll.).

> ⚠️ Jika kunci privat hilang, aplikasi yang sudah terpasang **tidak bisa** dipulihkan
> dengan kode darurat. Anda harus membuat kunci baru dan build ulang aplikasi.

### 3. Isi `secrets.json`

```json
{
  "TELEGRAM_BOT_TOKEN": "",
  "TELEGRAM_BOT_USERNAME": "",
  "RESCUE_PUBLIC_KEY": "q3J0...=",
  "DEVELOPER_WHATSAPP": "081234567890"
}
```

`DEVELOPER_WHATSAPP` adalah nomor Anda yang akan menerima permintaan. Format `08…`,
`628…`, atau `+62 8…` semuanya diterima.

### 4. Build aplikasi

```bash
flutter build apk --release --dart-define-from-file=secrets.json
```

---

## B. Saat Pemilik meminta bantuan

1. Pemilik mengirim pesan WhatsApp berisi **kode tantangan**, misalnya `7K3M-Q9TX`.
2. Di laptop, jalankan:

   ```bash
   dart run tool/kode_darurat.dart 7K3M-Q9TX
   ```

3. Salin pesan yang keluar (mulai dari `Kode darurat POS Apotek:` sampai akhir) dan
   kirim balik ke Pemilik lewat WhatsApp.
4. Pemilik menyalin pesan itu, menekan **Tempel kode** di aplikasi, lalu membuat PIN baru.
   Aplikasi juga memberi kode pemulihan baru.

Sebelum membuat kode, **pastikan yang meminta benar-benar Pemilik**, misalnya dengan
menelepon. Kode balasan membuka akun Pemilik.

---

## Pertanyaan umum

**Kode balasan ditolak?**
- Pastikan kode tantangan diketik dengan benar (huruf besar/kecil & strip tidak masalah).
- Kode tantangan berlaku 24 jam. Jika lewat, minta Pemilik membuka layar bantuan lagi
  untuk mendapat kode baru.
- Pastikan kunci publik di aplikasi cocok dengan kunci privat Anda:
  `dart run tool/kode_darurat.dart cek`, lalu bandingkan dengan `RESCUE_PUBLIC_KEY`.

**Ganti laptop?**
Pulihkan file kunci dari password manager ke lokasi yang sama, atau tunjuk lokasinya:
`dart run tool/kode_darurat.dart --kunci /path/kunci.txt 7K3M-Q9TX`

**Apakah kasir bisa membuat kode sendiri dengan membongkar aplikasi?**
Tidak. Aplikasi hanya berisi kunci publik, yang tidak bisa dipakai untuk membuat kode.
