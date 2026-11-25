import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import 'printer_settings.dart';

class PrinterException implements Exception {
  const PrinterException(this.message);
  final String message;
  @override
  String toString() => message;
}

class PairedPrinter {
  const PairedPrinter({required this.name, required this.address});
  final String name;
  final String address;
}

/// Mengirim byte ESC/POS ke printer thermal.
class PrinterService {
  Future<void> _queue = Future.value();

  /// Pekerjaan cetak dijalankan berurutan agar dua struk tidak bercampur.
  Future<void> send(PrinterSettings settings, Uint8List bytes) {
    final job = _queue.then((_) => _send(settings, bytes));
    _queue = job.catchError((Object _) {});
    return job;
  }

  Future<void> _send(PrinterSettings s, Uint8List bytes) => switch (s.type) {
    PrinterType.bluetooth => _sendBluetooth(s.btAddress, bytes),
    PrinterType.network => _sendNetwork(s.host, s.port, bytes),
    _ => throw const PrinterException('Printer thermal belum diatur'),
  };

  Future<void> _ensureBluetooth() async {
    if (!await PrintBluetoothThermal.isPermissionBluetoothGranted) {
      throw const PrinterException(
        'Izin Bluetooth belum diberikan. Buka Pengaturan HP → Aplikasi → '
        'POS Apotek → Izin → Perangkat sekitar → Izinkan.',
      );
    }
    if (!await PrintBluetoothThermal.bluetoothEnabled) {
      throw const PrinterException(
        'Bluetooth HP mati. Nyalakan Bluetooth lalu coba lagi.',
      );
    }
  }

  Future<List<PairedPrinter>> pairedDevices() async {
    await _ensureBluetooth();
    final list = await PrintBluetoothThermal.pairedBluetooths;
    return [
      for (final d in list) PairedPrinter(name: d.name, address: d.macAdress),
    ];
  }

  String? _connectedAddress;

  Future<void> _sendBluetooth(String address, Uint8List bytes) async {
    if (address.isEmpty) {
      throw const PrinterException('Printer Bluetooth belum dipilih');
    }
    await _ensureBluetooth();

    Future<bool> connect() async {
      if (_connectedAddress == address &&
          await PrintBluetoothThermal.connectionStatus) {
        return true;
      }
      if (await PrintBluetoothThermal.connectionStatus) {
        await PrintBluetoothThermal.disconnect;
      }
      final ok = await PrintBluetoothThermal.connect(macPrinterAddress: address)
          .timeout(const Duration(seconds: 12), onTimeout: () => false);
      _connectedAddress = ok ? address : null;
      return ok;
    }

    if (!await connect()) {
      throw const PrinterException(
        'Tidak bisa tersambung ke printer. Pastikan printer menyala, kertas '
        'terpasang, dan jaraknya dekat dengan HP.',
      );
    }
    var ok = await PrintBluetoothThermal.writeBytes(bytes);
    if (!ok) {
      // Sambungan lama sudah putus (mis. printer sempat dimatikan): sambung ulang sekali.
      _connectedAddress = null;
      ok = await connect() && await PrintBluetoothThermal.writeBytes(bytes);
    }
    if (!ok) {
      throw const PrinterException('Gagal mengirim ke printer. Coba lagi.');
    }
  }

  Future<void> _sendNetwork(String host, int port, Uint8List bytes) async {
    if (host.isEmpty) {
      throw const PrinterException('Alamat IP printer belum diisi');
    }
    Socket socket;
    try {
      socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 5),
      );
    } on SocketException {
      throw PrinterException(
        'Tidak bisa tersambung ke printer di $host:$port. Pastikan HP dan printer '
        'terhubung ke WiFi yang sama.',
      );
    }
    try {
      socket.add(bytes);
      await socket.flush();
    } finally {
      await socket.close();
      socket.destroy();
    }
  }
}

final printerServiceProvider = Provider<PrinterService>(
  (ref) => PrinterService(),
);
