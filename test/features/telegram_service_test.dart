import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pos_apotek/core/clock.dart';
import 'package:pos_apotek/core/config.dart';
import 'package:pos_apotek/core/database/app_database.dart';
import 'package:pos_apotek/core/format.dart';
import 'package:pos_apotek/features/auth/data/user_repository.dart';
import 'package:pos_apotek/features/products/data/product_models.dart';
import 'package:pos_apotek/features/products/data/product_repository.dart';
import 'package:pos_apotek/features/reports/data/report_service.dart';
import 'package:pos_apotek/features/sales/application/cart_controller.dart';
import 'package:pos_apotek/features/sales/data/sale_service.dart';
import 'package:pos_apotek/features/settings/data/settings_repository.dart';
import 'package:pos_apotek/features/shift/data/shift_service.dart';
import 'package:pos_apotek/features/telegram/data/telegram_api.dart';
import 'package:pos_apotek/features/telegram/data/telegram_messages.dart';
import 'package:pos_apotek/features/telegram/data/telegram_service.dart';

import '../helpers.dart';

/// Server Telegram palsu.
class FakeTelegram {
  final sent = <Map<String, dynamic>>[];
  final documents = <String>[];
  var offline = false;
  var updates = <Map<String, dynamic>>[];
  final tokens = <String>[];

  late final client = MockClient.streaming((req, body) async {
    if (offline) throw const SocketException('offline');
    final method = req.url.pathSegments.last;
    final bytes = await body.toBytes();
    Object? result = true;
    if (req.url.pathSegments.first.contains('DITOLAK')) {
      return http.StreamedResponse(
        Stream.value(
          utf8.encode(
            '{"ok":false,"error_code":401,"description":"Unauthorized"}',
          ),
        ),
        401,
      );
    }
    switch (method) {
      case 'getMe':
        result = {'username': 'bot_baru_bot'};
      case 'sendMessage':
        sent.add(jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>);
      case 'sendDocument':
        documents.add(utf8.decode(bytes, allowMalformed: true));
      case 'getUpdates':
        final args = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        final offset = args['offset'] as int? ?? 0;
        result = updates
            .where((u) => (u['update_id'] as int) >= offset)
            .toList();
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode({'ok': true, 'result': result}))),
      200,
    );
  });
}

void main() {
  late AppDatabase db;
  late FakeClock clock;
  late SettingsRepository settings;
  late TelegramOutboxWriter outbox;
  late TelegramService telegram;
  late FakeTelegram server;
  late ProductRepository products;
  late SaleService sales;
  late ShiftService shifts;
  late ProviderContainer container;
  late AppUser owner;
  late AppUser cashier;
  late ProductSummary para;
  late Directory temp;

  setUp(() async {
    db = memoryDatabase();
    clock = FakeClock(DateTime(2026, 11, 25, 8));
    settings = SettingsRepository(db, clock.call);
    server = FakeTelegram();
    temp = Directory.systemTemp.createTempSync('tg_');
    outbox = TelegramOutboxWriter(db, settings, clock.call);
    shifts = ShiftService(db, clock.call, notifier: outbox);
    products = ProductRepository(db, clock.call);
    sales = SaleService(db, products, clock.call, notifier: outbox);
    telegram = TelegramService(
      db: db,
      settings: settings,
      outbox: outbox,
      config: const AppConfig(
        telegramBotToken: 't',
        telegramBotUsername: 'apotek_bot',
      ),
      apiFactory: (token) {
        server.tokens.add(token);
        return TelegramApi(token, client: server.client);
      },
      now: clock.call,
      reports: ReportService(db, shifts),
      makeBackup: () async =>
          File('${temp.path}/b.zip')..writeAsStringSync('ZIPDATA'),
      makeShiftExcel: (id) async =>
          File('${temp.path}/shift.xlsx')..writeAsStringSync('EXCEL:$id'),
    );
    container = ProviderContainer(
      overrides: [clockProvider.overrideWithValue(clock.call)],
    );
    final users = UserRepository(db, fastHasher, clock.call);
    owner = await users.create(
      name: 'Sari',
      role: UserRole.owner,
      pin: '482915',
    );
    cashier = await users.create(
      name: 'Dewi',
      role: UserRole.cashier,
      pin: '739164',
    );
    final p = await products.create(
      const ProductInput(
        name: 'Paracetamol <500>',
        drugClass: DrugClass.bebas,
        units: [
          UnitInput(name: 'Tablet', multiplier: 1, sellPrice: 500),
          UnitInput(name: 'Strip', multiplier: 10, sellPrice: 4500),
        ],
      ),
    );
    final s = (await products.getOne(p.id))!;
    await products.receiveStock(
      productId: p.id,
      unit: s.baseUnit,
      quantity: 25,
      expiryDate: endOfMonth(2028, 1),
      costPerSelectedUnit: 300,
    );
    para = (await products.getOne(p.id))!;
  });

  tearDown(() async {
    container.dispose();
    await db.close();
    temp.deleteSync(recursive: true);
  });

  Future<Sale> sell(String unit, int qty) async {
    final fresh = (await products.getOne(para.product.id))!;
    container.read(cartProvider.notifier)
      ..clear()
      ..add(
        fresh,
        fresh.units.firstWhere((u) => u.name == unit),
        quantity: qty,
      );
    final c = container.read(cartProvider);
    return sales.complete(
      cart: c,
      method: PaymentMethod.cash,
      amountPaid: c.total,
      cashier: cashier,
    );
  }

  Future<int> pending() async =>
      (await db.select(db.telegramOutbox).get()).length;

  Future<void> link() async {
    final code = telegram.newLinkCode();
    server.updates = [
      {
        'update_id': 7,
        'message': {
          'text': '/start $code',
          'chat': {'id': 4242},
          'from': {'first_name': 'Sari'},
        },
      },
    ];
    expect(await telegram.waitForLink(code), 'Sari');
    await telegram.flush();
    expect(server.sent.single['text'], contains('Terhubung'));
    server.sent.clear();
  }

  test('belum terhubung: tidak ada yang diantrekan', () async {
    await shifts.open(by: cashier, openingCash: 0);
    await sell('Tablet', 1);
    expect(await pending(), 0);
  });

  test('menghubungkan lewat /start <kode>; kode lain diabaikan', () async {
    server.updates = [
      {
        'update_id': 1,
        'message': {
          'text': '/start salah',
          'chat': {'id': 1},
          'from': {},
        },
      },
    ];
    expect(
      await telegram.waitForLink('benar', timeout: const Duration(seconds: 0)),
      isNull,
    );
    await link();
    expect(await settings.get(TelegramKeys.chatId), '4242');
    expect(
      (await telegram.linkUri('abc')).toString(),
      'https://t.me/apotek_bot?start=abc',
    );
  });

  test(
    'transaksi & pembatalan terkirim; offline diantrekan lalu dikirim ulang',
    () async {
      await link();
      await shifts.open(by: cashier, openingCash: 0);

      server.offline = true;
      final sale = await sell('Strip', 1);
      expect(await pending(), 1, reason: 'tersimpan bersama transaksi');
      await telegram.flush();
      expect(await pending(), 1);
      final row = (await db.select(db.telegramOutbox).get()).single;
      expect(row.attempts, 1);

      server.offline = false;
      clock.advance(const Duration(minutes: 30));
      await telegram.flush();
      expect(await pending(), 0);
      final text = server.sent.single['text'] as String;
      expect(server.sent.single['chat_id'], 4242);
      expect(server.sent.single['parse_mode'], 'HTML');
      expect(text, contains('Penjualan ${sale.number}'));
      expect(text, contains('1 Strip Paracetamol &lt;500&gt; — Rp4.500'));
      expect(text, contains('Kasir: Dewi'));
      expect(text, contains('tertunda'));

      await sales.voidSale(saleId: sale.id, reason: 'salah <input>', by: owner);
      await telegram.flush();
      final voidText = server.sent.last['text'] as String;
      expect(voidText, contains('Transaksi dibatalkan'));
      expect(voidText, contains('oleh Sari'));
      expect(voidText, contains('salah &lt;input&gt;'));
    },
  );

  test('peringatan stok hanya saat baru menipis / habis', () async {
    await link();
    await shifts.open(by: cashier, openingCash: 0);
    await sell('Tablet', 10); // 25 → 15: aman
    await sell('Tablet', 7); // 15 → 8: baru menipis (< 1 Strip)
    await sell('Tablet', 1); // 8 → 7: sudah menipis, tidak diulang
    await sell('Tablet', 7); // → 0: habis
    await telegram.flush();
    final texts = server.sent.map((m) => m['text'] as String).toList();
    expect(texts[0], isNot(contains('Stok')));
    expect(
      texts[1],
      contains('⚠️ Stok menipis: Paracetamol &lt;500&gt; (sisa 8 Tablet)'),
    );
    expect(texts[2], isNot(contains('Stok')));
    expect(texts[3], contains('⛔ Stok habis'));
  });

  test('tutup shift: ringkasan + file backup; topik bisa dimatikan', () async {
    await link();
    await telegram.setTopic(TelegramTopic.sale, false);
    final shift = await shifts.open(by: cashier, openingCash: 50000);
    await sell('Strip', 1);
    await shifts.close(
      shiftId: shift.id,
      countedCash: 54000,
      by: cashier,
      note: 'kurang',
    );
    await telegram.flush();

    expect(server.sent, hasLength(1), reason: 'transaksi dimatikan');
    final text = server.sent.single['text'] as String;
    expect(text, contains('Tutup shift · Dewi'));
    expect(text, contains('Selisih: Kurang Rp500'));
    // Excel dulu, lalu backup.
    expect(server.documents, hasLength(2));
    expect(server.documents.first, contains('EXCEL:${shift.id}'));
    expect(server.documents.first, contains('Laporan Excel shift Dewi'));
    expect(server.documents.last, contains('ZIPDATA'));
    expect(server.documents.last, contains('4242'));
    expect(File('${temp.path}/shift.xlsx').existsSync(), isFalse);

    // Excel bisa dimatikan sendiri.
    await telegram.setTopic(TelegramTopic.shiftExcel, false);
    final next = await shifts.open(by: cashier, openingCash: 54000);
    await shifts.close(shiftId: next.id, countedCash: 54000, by: cashier);
    await telegram.flush();
    expect(server.documents, hasLength(3));
    expect(server.documents.last, contains('ZIPDATA'));
    expect(
      File('${temp.path}/b.zip').existsSync(),
      isFalse,
      reason: 'file sementara dihapus',
    );
  });

  test('ringkasan harian sekali per hari, setelah hari berganti', () async {
    await link();
    await shifts.open(by: owner, openingCash: 0);
    await telegram.setTopic(TelegramTopic.sale, false);
    await sell('Strip', 2);

    await telegram.queueDailySummaries();
    expect(await pending(), 0, reason: 'hari belum berganti');

    clock.advance(const Duration(days: 1));
    await telegram.queueDailySummaries();
    await telegram.queueDailySummaries();
    await telegram.flush();
    final text = server.sent.single['text'] as String;
    expect(text, contains('Ringkasan Rabu, 25 November 2026'));
    expect(text, contains('Omzet <b>Rp9.000</b> (1 transaksi)'));
    expect(text, contains('2 Strip'));
    expect(text, contains('masih buka'));
  });

  test('putuskan: antrean dihapus, tidak ada lagi yang diantrekan', () async {
    await link();
    server.offline = true;
    await telegram.sendTest();
    expect(await pending(), 1);
    await telegram.unlink();
    expect(await pending(), 0);
    await shifts.open(by: cashier, openingCash: 0);
    await sell('Tablet', 1);
    expect(await pending(), 0);
  });

  test('pesan harian kosong', () async {
    final r = await ReportService(
      db,
      shifts,
    ).build(ReportRange.day(DateTime(2026, 11, 23)));
    expect(dailyMessage(r), contains('Senin, 23 November 2026'));
    expect(dailyMessage(r), contains('Tidak ada transaksi'));
  });

  group('token bot diisi di aplikasi', () {
    const good = '123456789:AAHk3abcdefghijklmnopqrstuvwxyz012';

    test('format salah ditolak tanpa menghubungi Telegram', () async {
      await expectLater(
        telegram.saveToken('bukan token'),
        throwsA(isA<TelegramException>()),
      );
      expect(server.tokens, isEmpty);
    });

    test('token ditolak Telegram', () async {
      await expectLater(
        telegram.saveToken('123456789:DITOLAKabcdefghijklmnopqrstuvwxyz'),
        throwsA(
          isA<TelegramException>().having(
            (e) => e.message,
            'pesan',
            contains('ditolak'),
          ),
        ),
      );
      expect((await telegram.credentials())!.fromBuild, isTrue);
    });

    test(
      'token baru menggantikan bot build & memutus sambungan lama',
      () async {
        await link();
        expect(await telegram.saveToken('  $good\n'), 'bot_baru_bot');
        final c = (await telegram.credentials())!;
        expect(c.token, good);
        expect(c.username, 'bot_baru_bot');
        expect(c.fromBuild, isFalse);
        expect(
          await settings.get(TelegramKeys.chatId),
          '',
          reason: 'harus START bot baru',
        );
        expect(
          (await telegram.linkUri('x')).toString(),
          'https://t.me/bot_baru_bot?start=x',
        );

        // Token sama disimpan ulang → sambungan tetap.
        await settings.set(TelegramKeys.chatId, '99');
        await telegram.saveToken(good);
        expect(await settings.get(TelegramKeys.chatId), '99');

        await telegram.removeToken();
        expect((await telegram.credentials())!.fromBuild, isTrue);
        await telegram.stop();
      },
    );
  });

  test('tanpa token build maupun isian: tidak aktif', () async {
    final none = TelegramService(
      db: db,
      settings: settings,
      outbox: outbox,
      config: const AppConfig(),
      apiFactory: (t) => TelegramApi(t, client: server.client),
      now: clock.call,
      reports: ReportService(db, shifts),
      makeBackup: () async => File('x'),
      makeShiftExcel: (_) async => File('x'),
    );
    expect(await none.credentials(), isNull);
    await none.flush();
    expect(server.tokens, isEmpty);
  });
}
