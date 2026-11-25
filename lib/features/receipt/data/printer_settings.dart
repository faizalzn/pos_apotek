import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/data/settings_repository.dart';
import 'receipt_layout.dart';

enum PrinterType {
  none('Belum diatur'),
  bluetooth('Printer thermal Bluetooth'),
  network('Printer thermal WiFi / LAN'),
  android('Printer lain (lewat layanan cetak Android)');

  const PrinterType(this.label);
  final String label;

  static PrinterType fromName(String? name) =>
      values.firstWhere((t) => t.name == name, orElse: () => none);
}

abstract final class PrinterKeys {
  static const type = 'printer.type';
  static const btAddress = 'printer.bt_address';
  static const btName = 'printer.bt_name';
  static const host = 'printer.host';
  static const port = 'printer.port';
  static const paper = 'printer.paper';
  static const autoPrint = 'printer.auto_print';
  static const showLogo = 'receipt.show_logo';

  /// Nama file logo di folder foto (ikut ter-backup).
  static const logoFile = 'store.logo_file';
}

class PrinterSettings {
  const PrinterSettings({
    this.type = PrinterType.none,
    this.btAddress = '',
    this.btName = '',
    this.host = '',
    this.port = 9100,
    this.paper = PaperWidth.mm58,
    this.autoPrint = true,
    this.showLogo = true,
    this.logoFile,
  });

  final PrinterType type;
  final String btAddress;
  final String btName;
  final String host;
  final int port;
  final PaperWidth paper;

  /// Cetak otomatis setelah transaksi selesai.
  final bool autoPrint;
  final bool showLogo;
  final String? logoFile;

  bool get isThermal =>
      type == PrinterType.bluetooth || type == PrinterType.network;

  bool get isReady => switch (type) {
    PrinterType.none => false,
    PrinterType.bluetooth => btAddress.isNotEmpty,
    PrinterType.network => host.isNotEmpty,
    PrinterType.android => true,
  };

  String get description => switch (type) {
    PrinterType.none => 'Belum diatur',
    PrinterType.bluetooth =>
      btName.isEmpty ? 'Bluetooth' : 'Bluetooth · $btName',
    PrinterType.network => 'WiFi · $host:$port',
    PrinterType.android => 'Layanan cetak Android',
  };

  static PrinterSettings fromMap(Map<String, String> m) => PrinterSettings(
    type: PrinterType.fromName(m[PrinterKeys.type]),
    btAddress: m[PrinterKeys.btAddress] ?? '',
    btName: m[PrinterKeys.btName] ?? '',
    host: m[PrinterKeys.host] ?? '',
    port: int.tryParse(m[PrinterKeys.port] ?? '') ?? 9100,
    paper: PaperWidth.fromName(m[PrinterKeys.paper]),
    autoPrint: m[PrinterKeys.autoPrint] != 'false',
    showLogo: m[PrinterKeys.showLogo] != 'false',
    logoFile: (m[PrinterKeys.logoFile] ?? '').isEmpty
        ? null
        : m[PrinterKeys.logoFile],
  );

  /// Hanya pengaturan printer (logo disimpan terpisah).
  Map<String, String> toMap() => {
    PrinterKeys.type: type.name,
    PrinterKeys.btAddress: btAddress,
    PrinterKeys.btName: btName,
    PrinterKeys.host: host.trim(),
    PrinterKeys.port: '$port',
    PrinterKeys.paper: paper.name,
    PrinterKeys.autoPrint: '$autoPrint',
    PrinterKeys.showLogo: '$showLogo',
  };

  PrinterSettings copyWith({
    PrinterType? type,
    String? btAddress,
    String? btName,
    String? host,
    int? port,
    PaperWidth? paper,
    bool? autoPrint,
    bool? showLogo,
  }) => PrinterSettings(
    type: type ?? this.type,
    btAddress: btAddress ?? this.btAddress,
    btName: btName ?? this.btName,
    host: host ?? this.host,
    port: port ?? this.port,
    paper: paper ?? this.paper,
    autoPrint: autoPrint ?? this.autoPrint,
    showLogo: showLogo ?? this.showLogo,
    logoFile: logoFile,
  );
}

final printerSettingsProvider = StreamProvider<PrinterSettings>(
  (ref) => ref
      .watch(settingsRepositoryProvider)
      .watchAll()
      .map(PrinterSettings.fromMap),
);
