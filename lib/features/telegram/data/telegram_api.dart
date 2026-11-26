import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Kesalahan dari Telegram atau jaringan.
class TelegramException implements Exception {
  const TelegramException(this.message, {this.statusCode, this.retryAfter});

  final String message;

  /// `null` = gagal jaringan (offline), coba lagi nanti.
  final int? statusCode;

  /// Detik yang diminta Telegram sebelum mencoba lagi (HTTP 429).
  final int? retryAfter;

  bool get isNetwork => statusCode == null;

  /// Pesan ini tidak akan pernah berhasil (mis. format salah) → buang.
  bool get isPermanent => statusCode == 400;

  /// Bot diblokir / chat tidak ditemukan → perlu dihubungkan ulang.
  bool get needsRelink => statusCode == 403 || statusCode == 401;

  @override
  String toString() => message;
}

/// Pesan masuk ke bot (hanya yang dibutuhkan untuk menghubungkan).
class TelegramUpdate {
  const TelegramUpdate({
    required this.updateId,
    required this.chatId,
    required this.text,
    required this.name,
  });

  final int updateId;
  final int? chatId;
  final String text;
  final String name;
}

/// Klien Bot API Telegram yang sangat kecil.
class TelegramApi {
  TelegramApi(this._token, {http.Client? client})
    : _client = client ?? http.Client();

  final String _token;
  final http.Client _client;

  static const _timeout = Duration(seconds: 30);

  Uri _uri(String method) =>
      Uri.parse('https://api.telegram.org/bot$_token/$method');

  Future<dynamic> _call(
    Future<http.Response> Function() send, {
    Duration timeout = _timeout,
  }) async {
    final http.Response res;
    try {
      res = await send().timeout(timeout);
    } on Exception catch (_) {
      // SocketException, TimeoutException, ClientException, ...
      throw const TelegramException('Tidak ada koneksi internet');
    }
    Map<String, dynamic> body;
    try {
      body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } on FormatException {
      throw TelegramException(
        'Jawaban Telegram tidak dikenali',
        statusCode: res.statusCode,
      );
    }
    if (body['ok'] == true) return body['result'];
    final params = body['parameters'] as Map<String, dynamic>?;
    throw TelegramException(
      '${body['description'] ?? 'Gagal'}',
      statusCode: res.statusCode,
      retryAfter: params?['retry_after'] as int?,
    );
  }

  Future<void> sendMessage(int chatId, String html) => _call(
    () => _client.post(
      _uri('sendMessage'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'chat_id': chatId,
        'text': html,
        'parse_mode': 'HTML',
        'disable_web_page_preview': true,
      }),
    ),
  );

  Future<void> sendDocument(int chatId, File file, {String caption = ''}) =>
      _call(() async {
        final req = http.MultipartRequest('POST', _uri('sendDocument'))
          ..fields['chat_id'] = '$chatId'
          ..fields['caption'] = caption
          ..fields['parse_mode'] = 'HTML'
          ..files.add(await http.MultipartFile.fromPath('document', file.path));
        return http.Response.fromStream(await _client.send(req));
      }, timeout: const Duration(minutes: 3));

  /// Pesan baru sejak [offset]. [wait] = long polling (detik).
  Future<List<TelegramUpdate>> getUpdates({int? offset, int wait = 0}) async {
    final result = await _call(
      () => _client.post(
        _uri('getUpdates'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'offset': ?offset,
          'timeout': wait,
          'allowed_updates': ['message'],
        }),
      ),
      timeout: Duration(seconds: wait + 15),
    ) as List<dynamic>;
    return [
      for (final u in result.cast<Map<String, dynamic>>())
        TelegramUpdate(
          updateId: u['update_id'] as int,
          chatId: (u['message']?['chat']?['id']) as int?,
          text: (u['message']?['text'] as String?) ?? '',
          name: [
            u['message']?['from']?['first_name'],
            u['message']?['from']?['last_name'],
          ].whereType<String>().join(' '),
        ),
    ];
  }
}
