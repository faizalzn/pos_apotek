import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/format.dart';

/// Kode QR berlatar putih (agar terbaca walau tema gelap).
class QrisCode extends StatelessWidget {
  const QrisCode({super.key, required this.data, this.size = 260});

  final String data;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.black12),
    ),
    child: QrImageView(
      data: data,
      size: size,
      // QRIS memakai koreksi galat level M.
      errorCorrectionLevel: QrErrorCorrectLevel.M,
      backgroundColor: Colors.white,
      semanticsLabel: 'Kode QRIS',
    ),
  );
}

/// Layar penuh untuk diperlihatkan ke pelanggan.
class QrisFullScreen extends StatelessWidget {
  const QrisFullScreen({
    super.key,
    required this.data,
    required this.amount,
    required this.merchantName,
  });

  final String data;
  final int amount;
  final String merchantName;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final qrSize = (size.shortestSide * 0.8).clamp(200.0, 520.0);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        title: const Text('Scan untuk membayar'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                merchantName,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 20, color: Colors.black87),
              ),
              const SizedBox(height: 4),
              Text(
                formatRupiah(amount),
                style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 16),
              QrisCode(data: data, size: qrSize),
              const SizedBox(height: 16),
              const Text(
                'Buka aplikasi bank / e-wallet → Scan QRIS.\n'
                'Nominal sudah terisi otomatis.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.black87),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
