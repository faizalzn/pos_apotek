import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Sumber waktu "sekarang". Diganti di pengujian agar waktu bisa dikendalikan.
typedef Clock = DateTime Function();

final clockProvider = Provider<Clock>((ref) => DateTime.now);
