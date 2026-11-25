# ADR-0007: Stok per batch & tanggal kedaluwarsa (FEFO)

- **Status:** Diterima
- **Tanggal:** 2026-11-25

## Konteks

Satu obat dapat memiliki beberapa batch dengan tanggal kedaluwarsa (ED) berbeda.
Obat juga dijual dalam beberapa satuan (box, strip, tablet), termasuk eceran.

## Keputusan

- Stok disimpan **per batch** (no. batch, ED, jumlah, harga beli) dalam **satuan terkecil**.
- Produk memiliki **satuan bertingkat** dengan faktor konversi, harga jual, dan barcode masing-masing.
- Penjualan mengurangi stok dari batch dengan **ED terdekat lebih dulu (FEFO)**.
- Setiap perubahan stok dicatat di tabel **riwayat stok** untuk penelusuran.
- Golongan obat (bebas, bebas terbatas, keras, psikotropika) dicatat sebagai label;
  obat keras memunculkan peringatan "perlu resep" saat dijual.

## Konsekuensi

- Peringatan ED dan stok menipis dapat dihitung akurat.
- Input stok sedikit lebih panjang (perlu ED & batch), dibantu nilai bawaan.
