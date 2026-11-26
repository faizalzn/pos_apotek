import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:async/async.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/clock.dart';
import '../../../core/config.dart';
import '../../../core/database/app_database.dart';
import '../../backup/data/backup_service.dart';
import '../../reports/data/report_service.dart';
import '../../sales/data/sale_service.dart';
import '../../settings/data/settings_repository.dart';
import '../../shift/data/shift_service.dart';
import 'telegram_api.dart';
import 'telegram_messages.dart';

abstract final class TelegramKeys {
  static const chatId = 'telegram.chat_id';
  static const chatName = 'telegram.chat_name';
  static const notifySale = 'telegram.notify_sale';
  static const notifyVoid = 'telegram.notify_void';
  static const notifyShift = 'telegram.notify_shift';
  static const notifyDaily = 'telegram.notify_daily';
  static const sendBackup = 'telegram.send_backup';

  /// Tanggal terakhir yang ringkasan hariannya sudah diantrekan (yyyy-MM-dd).
  static const dailyLast = 'telegram.daily_last';
}

/// Jenis notifikasi yang bisa dinyalakan/dimatikan Pemilik.
enum TelegramTopic {
  sale(
    TelegramKeys.notifySale,
    'Setiap transaksi',
    'Isi belanja, total, cara bayar, peringatan stok',
  ),
  voided(
    TelegramKeys.notifyVoid,
    'Transaksi dibatalkan',
    'Siapa, kapan, dan alasannya',
  ),
  shift(
    TelegramKeys.notifyShift,
    'Tutup shift',
    'Uang seharusnya, hitungan, dan selisih',
  ),
  daily(
    TelegramKeys.notifyDaily,
    'Ringkasan harian',
    'Dikirim setelah hari berganti saat aplikasi dibuka',
  ),
  backup(
    TelegramKeys.sendBackup,
    'Backup saat tutup shift',
    'File backup data (tanpa foto) dikirim ke Telegram',
  );

  const TelegramTopic(this.key, this.label, this.description);
  final String key;
  final String label;
  final String description;
}

String _ymd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Menulis pesan ke antrean. Dipanggil dari dalam transaksi database
/// penjualan/shift, sehingga pesan tersimpan bersama datanya.
class TelegramOutboxWriter implements SaleNotifier, ShiftNotifier {
  TelegramOutboxWriter(
    this._db,
    this._settings,
    this._now, {
    required this.enabled,
  });

  final AppDatabase _db;
  final SettingsRepository _settings;
  final Clock _now;

  /// Token bot tersedia di build ini.
  final bool enabled;

  static const _uuid = Uuid();

  Future<bool> wants(TelegramTopic topic) async {
    if (!enabled) return false;
    final all = await _settings.getAll();
    return (all[TelegramKeys.chatId] ?? '').isNotEmpty && all[topic.key] != '0';
  }

  Future<void> add(String body, {OutboxKind kind = OutboxKind.text}) => _db
      .into(_db.telegramOutbox)
      .insert(
        TelegramOutboxCompanion.insert(
          id: _uuid.v4(),
          kind: kind,
          body: body,
          createdAt: _now(),
        ),
      );

  @override
  Future<void> saleCompleted(SaleDetail detail, List<StockNote> stock) async {
    if (await wants(TelegramTopic.sale)) {
      await add(saleMessage(detail, stock: stock));
    }
  }

  @override
  Future<void> saleVoided(SaleDetail detail) async {
    if (await wants(TelegramTopic.voided)) await add(voidMessage(detail));
  }

  @override
  Future<void> shiftClosed(ShiftSummary summary) async {
    if (await wants(TelegramTopic.shift)) {
      await add(shiftClosedMessage(summary));
    }
    if (await wants(TelegramTopic.backup)) {
      await add(
        '💾 Backup data setelah tutup shift ${escapeHtml(summary.openedByName)}',
        kind: OutboxKind.backup,
      );
    }
  }
}

/// Status untuk layar pengaturan.
class TelegramStatus {
  const TelegramStatus({
    required this.enabled,
    required this.chatName,
    required this.pending,
    required this.lastError,
    required this.topics,
  });

  /// Token bot tersedia di build ini.
  final bool enabled;
  final String? chatName;
  final int pending;
  final String? lastError;
  final Map<TelegramTopic, bool> topics;

  bool get linked => chatName != null;
}

/// Mengirim antrean, menghubungkan akun, dan menjadwalkan ringkasan harian.
class TelegramService {
  TelegramService({
    required this._db,
    required this._settings,
    required this._outbox,
    required this.config,
    required this._api,
    required this._now,
    required this._reports,
    required this._makeBackup,
  });

  final AppDatabase _db;
  final SettingsRepository _settings;
  final TelegramOutboxWriter _outbox;
  final AppConfig config;
  final TelegramApi? _api;
  final Clock _now;
  final ReportService _reports;
  final Future<File> Function() _makeBackup;

  bool get enabled => _api != null;

  Timer? _timer;
  StreamSubscription<void>? _sub;
  Future<void>? _flushing;
  DateTime? _pauseUntil;
  final _error = StreamController<String?>.broadcast();
  String? _lastError;

  void _setError(String? e) {
    if (e == _lastError) return;
    _lastError = e;
    _error.add(e);
  }

  /// Mulai bekerja di latar: kirim antrean saat ada pesan baru & tiap menit.
  void start() {
    if (!enabled || _timer != null) return;
    _sub = _db
        .tableUpdates(
          TableUpdateQuery.onTable(
            _db.telegramOutbox,
            limitUpdateKind: UpdateKind.insert,
          ),
        )
        .listen((_) => unawaited(flush()));
    _timer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => unawaited(tick()),
    );
    unawaited(tick());
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    await _sub?.cancel();
    _sub = null;
    await _flushing;
    await _error.close();
  }

  Future<void> tick() async {
    try {
      await queueDailySummaries();
    } on Object catch (e) {
      debugPrint('Ringkasan harian gagal: $e');
    }
    await flush();
  }

  Future<int?> _chatId() async =>
      int.tryParse(await _settings.get(TelegramKeys.chatId) ?? '');

  /// Kirim semua pesan yang mengantre. Aman dipanggil berkali-kali.
  Future<void> flush({bool force = false}) {
    if (force) _pauseUntil = null;
    return _flushing ??= _flush().whenComplete(() => _flushing = null);
  }

  Future<void> _flush() async {
    final api = _api;
    if (api == null) return;
    if (_pauseUntil case final until? when _now().isBefore(until)) return;
    final chat = await _chatId();
    if (chat == null) return;
    while (true) {
      final rows =
          await (_db.select(_db.telegramOutbox)
                ..orderBy([(o) => OrderingTerm.asc(o.createdAt)])
                ..limit(20))
              .get();
      if (rows.isEmpty) {
        _setError(null);
        return;
      }
      for (final row in rows) {
        try {
          await _send(api, chat, row);
          await (_db.delete(
            _db.telegramOutbox,
          )..where((o) => o.id.equals(row.id))).go();
        } on TelegramException catch (e) {
          if (e.isPermanent && row.attempts >= 2) {
            // Pesan rusak tidak boleh menahan antrean selamanya.
            await (_db.delete(
              _db.telegramOutbox,
            )..where((o) => o.id.equals(row.id))).go();
            continue;
          }
          await (_db.update(
            _db.telegramOutbox,
          )..where((o) => o.id.equals(row.id))).write(
            TelegramOutboxCompanion(
              attempts: Value(row.attempts + 1),
              lastError: Value(e.message),
            ),
          );
          if (e.retryAfter != null) {
            _pauseUntil = _now().add(Duration(seconds: e.retryAfter!));
          }
          _setError(
            e.isNetwork
                ? 'Menunggu internet'
                : e.needsRelink
                ? 'Telegram menolak pesan. Hubungkan ulang (bot mungkin diblokir).'
                : 'Gagal mengirim: ${e.message}',
          );
          return;
        } on FileSystemException catch (e) {
          _setError('Backup gagal dibuat: ${e.message}');
          await (_db.delete(
            _db.telegramOutbox,
          )..where((o) => o.id.equals(row.id))).go();
        }
      }
    }
  }

  Future<void> _send(TelegramApi api, int chat, TelegramOutboxData row) async {
    switch (row.kind) {
      case OutboxKind.text:
        final late =
            _now().difference(row.createdAt) > const Duration(minutes: 10);
        await api.sendMessage(
          chat,
          late
              ? '${row.body}\n<i>(tertunda, tidak ada internet)</i>'
              : row.body,
        );
      case OutboxKind.backup:
        final file = await _makeBackup();
        try {
          await api.sendDocument(
            chat,
            file,
            caption:
                '${row.body}\nSimpan file ini. Untuk memulihkan: Pengaturan → Backup & Pulihkan.',
          );
        } finally {
          if (await file.exists()) await file.delete();
        }
    }
  }

  /// Antrekan ringkasan untuk hari-hari yang sudah lewat (maks. 7 hari).
  Future<void> queueDailySummaries() async {
    if (!await _outbox.wants(TelegramTopic.daily)) return;
    final now = _now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(today.year, today.month, today.day - 1);
    final last = DateTime.tryParse(
      await _settings.get(TelegramKeys.dailyLast) ?? '',
    );
    if (last != null && !last.isBefore(yesterday)) return;
    var day = last == null
        ? yesterday
        : DateTime(last.year, last.month, last.day + 1);
    final earliest = DateTime(today.year, today.month, today.day - 7);
    if (day.isBefore(earliest)) day = earliest;
    await _db.transaction(() async {
      for (
        ;
        !day.isAfter(yesterday);
        day = DateTime(day.year, day.month, day.day + 1)
      ) {
        final report = await _reports.build(ReportRange.day(day));
        if (report.count > 0 || report.voidCount > 0) {
          await _outbox.add(dailyMessage(report));
        }
      }
      await _settings.set(TelegramKeys.dailyLast, _ymd(yesterday));
    });
  }

  /// Ringkasan hari ini (tombol di pengaturan).
  Future<void> queueTodaySummary() async {
    final report = await _reports.build(ReportRange.day(_now()));
    await _outbox.add(dailyMessage(report));
  }

  // ---------------- Menghubungkan ----------------

  /// Kode acak untuk tautan `t.me/<bot>?start=<kode>`.
  String newLinkCode() {
    const chars = 'abcdefghijkmnpqrstuvwxyz23456789';
    final r = Random.secure();
    return List.generate(12, (_) => chars[r.nextInt(chars.length)]).join();
  }

  Uri linkUri(String code) =>
      Uri.https('t.me', '/${config.telegramBotUsername}', {'start': code});

  /// Menunggu Pemilik menekan Start di bot. Mengembalikan nama akun
  /// Telegram, atau `null` bila waktu habis / dibatalkan.
  Future<String?> waitForLink(
    String code, {
    Duration timeout = const Duration(minutes: 3),
    bool Function()? cancelled,
  }) async {
    final api = _api!;
    final end = _now().add(timeout);
    int? offset;
    while (_now().isBefore(end) && !(cancelled?.call() ?? false)) {
      final List<TelegramUpdate> updates;
      try {
        updates = await api.getUpdates(offset: offset, wait: 10);
      } on TelegramException catch (e) {
        if (!e.isNetwork) rethrow;
        await Future<void>.delayed(const Duration(seconds: 3));
        continue;
      }
      for (final u in updates) {
        offset = u.updateId + 1;
        if (u.chatId != null && u.text.trim() == '/start $code') {
          // Tandai pesan sudah dibaca agar tidak diproses lagi.
          await api.getUpdates(offset: offset);
          await _link(u.chatId!, u.name.isEmpty ? 'Telegram' : u.name);
          return u.name.isEmpty ? 'Telegram' : u.name;
        }
      }
    }
    if (offset != null) await api.getUpdates(offset: offset);
    return null;
  }

  Future<void> _link(int chatId, String name) async {
    final yesterday = _now().subtract(const Duration(days: 1));
    await _db.transaction(() async {
      await _db.delete(_db.telegramOutbox).go();
      await _settings.setAll({
        TelegramKeys.chatId: '$chatId',
        TelegramKeys.chatName: name,
        // Ringkasan dimulai dari hari ini, bukan riwayat lama.
        TelegramKeys.dailyLast: _ymd(yesterday),
      });
    });
    final store = await _settings.get(SettingKeys.storeName) ?? 'apotek';
    await _outbox.add(
      '✅ <b>Terhubung</b>\nNotifikasi POS Apotek "${escapeHtml(store)}" akan dikirim ke sini.',
    );
  }

  Future<void> unlink() => _db.transaction(() async {
    await _db.delete(_db.telegramOutbox).go();
    await _settings.setAll({
      TelegramKeys.chatId: '',
      TelegramKeys.chatName: '',
    });
  });

  Future<void> sendTest() => _outbox.add(
    '🔔 Pesan uji dari POS Apotek. Notifikasi berjalan dengan baik.',
  );

  Future<void> setTopic(TelegramTopic topic, bool on) =>
      _settings.set(topic.key, on ? '1' : '0');

  Stream<TelegramStatus> watchStatus() async* {
    Future<TelegramStatus> load() async {
      final all = await _settings.getAll();
      final pending = await _db
          .customSelect(
            'SELECT COUNT(*) AS n FROM telegram_outbox',
            readsFrom: {_db.telegramOutbox},
          )
          .getSingle();
      final name = all[TelegramKeys.chatName] ?? '';
      return TelegramStatus(
        enabled: enabled,
        chatName: (all[TelegramKeys.chatId] ?? '').isEmpty || name.isEmpty
            ? null
            : name,
        pending: pending.read<int>('n'),
        lastError: _lastError,
        topics: {for (final t in TelegramTopic.values) t: all[t.key] != '0'},
      );
    }

    yield await load();
    yield* StreamGroup.mergeBroadcast<void>([
      _db.tableUpdates(
        TableUpdateQuery.onAllTables([_db.telegramOutbox, _db.appSettings]),
      ),
      _error.stream,
    ]).asyncMap((_) => load());
  }
}

final telegramOutboxProvider = Provider<TelegramOutboxWriter>(
  (ref) => TelegramOutboxWriter(
    ref.watch(databaseProvider),
    ref.watch(settingsRepositoryProvider),
    ref.watch(clockProvider),
    enabled: ref.watch(appConfigProvider).telegramEnabled,
  ),
);

final telegramServiceProvider = Provider<TelegramService>((ref) {
  final config = ref.watch(appConfigProvider);
  final service = TelegramService(
    db: ref.watch(databaseProvider),
    settings: ref.watch(settingsRepositoryProvider),
    outbox: ref.watch(telegramOutboxProvider),
    config: config,
    api: config.telegramEnabled ? TelegramApi(config.telegramBotToken) : null,
    now: ref.watch(clockProvider),
    reports: ref.watch(reportServiceProvider),
    makeBackup: () async =>
        (await ref.read(backupServiceProvider.future)).createForTelegram(),
  );
  ref.onDispose(service.stop);
  return service;
});

final telegramStatusProvider = StreamProvider<TelegramStatus>(
  (ref) => ref.watch(telegramServiceProvider).watchStatus(),
);

/// Menyalakan pengirim antrean (tidak melakukan apa pun bila token kosong).
final telegramRunnerProvider = Provider<void>((ref) {
  ref.watch(telegramServiceProvider).start();
});
