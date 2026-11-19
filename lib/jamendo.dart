import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'music_library.dart';

class JamendoException implements Exception {
  final String message;
  const JamendoException(this.message);
  @override
  String toString() => message;
}

class JamendoPage {
  final List<OnlineMusicTrack> tracks;
  final bool hasMore;
  const JamendoPage(this.tracks, {this.hasMore = false});
}

/// The decoder receives only this localhost MP3 stream, never a remote URL.
/// Every upstream redirect stays inside the validated Dart transport. No disk cache.
class JamendoPreview {
  final OnlineMusicTrack track;
  final HttpServer _server;
  final Stream<List<int>> Function(void Function(HttpClient)) _source;
  final _clients = <HttpClient>{};
  final _streams = <StreamIterator<List<int>>>{};
  final String _token;
  int _requests = 0;
  bool _closed = false;
  JamendoPreview._(this._server, this._source, this._token, this.track);
  Uri get uri => Uri(
    scheme: 'http',
    host: '127.0.0.1',
    port: _server.port,
    path: '/$_token.mp3',
  );
  static Future<JamendoPreview> start(
    OnlineMusicTrack track,
    Stream<List<int>> Function(void Function(HttpClient)) source,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final random = Random.secure();
    final token = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final preview = JamendoPreview._(server, source, token, track);
    server.listen(
      (request) => unawaited(preview._serve(request)),
      onError: (Object _) {},
    );
    return preview;
  }

  Future<void> _serve(HttpRequest request) async {
    StreamIterator<List<int>>? stream;
    try {
      if (_closed ||
          request.uri.path != uri.path ||
          request.uri.hasQuery ||
          !{'GET', 'HEAD'}.contains(request.method) ||
          _requests++ >= 8) {
        request.response.statusCode = 403;
        await request.response.close();
        return;
      }
      request.response.headers.contentType = ContentType('audio', 'mpeg');
      request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'none');
      request.response.bufferOutput = false;
      if (request.method == 'GET') {
        stream = StreamIterator(
          _source((client) {
            if (_closed) {
              client.close(force: true);
            } else {
              _clients.add(client);
            }
          }),
        );
        _streams.add(stream);
        while (!_closed && await stream.moveNext()) {
          request.response.add(stream.current);
          await request.response.flush();
        }
      }
      await request.response.close();
    } catch (_) {
      try {
        await request.response.close();
      } catch (_) {}
    } finally {
      if (stream != null) {
        _streams.remove(stream);
        try {
          await stream.cancel();
        } catch (_) {
          // Closing the HTTP client can fail a pending upstream read.
        }
      }
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final client in _clients) {
      client.close(force: true);
    }
    _clients.clear();
    final closing = _server.close(force: true);
    for (final stream in _streams.toList()) {
      try {
        await stream.cancel();
      } catch (_) {
        // Cancellation intentionally closes the active network request.
      }
    }
    _streams.clear();
    await closing;
  }
}

typedef JamendoJson = Future<Map<String, dynamic>> Function(
  Map<String, String> parameters,
);

class JamendoProvider implements OnlineMusicProvider {
  final String clientId;
  // Only a distributor build with documented Jamendo permission may enable this.
  // It is deliberately not a user preference or a checkbox in the application.
  final bool editingApproved;
  final JamendoJson? getJson;
  final Stream<List<int>> Function(Uri)? audioStream;
  final _cache = <String, (DateTime, JamendoPage)>{};
  static const pageSize = 20;
  static const sorts = {
    'relevance': 'По умолчанию',
    'popularity_month': 'Популярное за месяц',
    'releasedate_desc': 'Сначала новые',
  };
  JamendoProvider({
    required String clientId,
    this.editingApproved = false,
    this.getJson,
    this.audioStream,
  }) : clientId = clientId.trim();
  @override
  String get id => 'jamendo';
  @override
  String get displayName => 'Jamendo';
  @override
  String? get unavailableReason =>
      RegExp(r'^[A-Za-z0-9_-]{4,128}$').hasMatch(clientId)
      ? null
      : 'Подключи Jamendo: укажи Client ID приложения.';

  static bool safeAudio(Uri? uri) =>
      uri != null &&
      uri.scheme == 'https' &&
      uri.userInfo.isEmpty &&
      uri.port == 443 &&
      (RegExp(r'^prod-\d+\.storage\.jamendo\.com$').hasMatch(uri.host) ||
          {'mp3l.jamendo.com', 'usercontent.jamendo.com'}.contains(uri.host));

  static OnlineMusicTrack? parseTrack(
    Map<String, dynamic> j, {
    bool editingApproved = false,
  }) {
    final id = '${j['id'] ?? ''}';
    final title = j['name'];
    final seconds = j['duration'];
    if (!RegExp(r'^\d{1,20}$').hasMatch(id) ||
        title is! String ||
        title.trim().isEmpty ||
        seconds is! num ||
        !seconds.isFinite ||
        seconds <= 0 ||
        seconds > 86400) {
      return null;
    }
    Uri? audio(String key) {
      final uri = Uri.tryParse('${j[key] ?? ''}');
      return safeAudio(uri) ? uri : null;
    }

    final preview = audio('audio');
    if (preview == null) return null;
    final rawLicense = Uri.tryParse('${j['license_ccurl'] ?? ''}');
    final cc =
        rawLicense != null &&
        rawLicense.userInfo.isEmpty &&
        {
          'creativecommons.org',
          'www.creativecommons.org',
        }.contains(rawLicense.host) &&
        {'http', 'https'}.contains(rawLicense.scheme);
    final license = cc ? rawLicense.replace(scheme: 'https') : null;
    final parts = license?.pathSegments ?? <String>[];
    final by =
        parts.length >= 3 &&
        parts[0] == 'licenses' &&
        parts[1] == 'by' &&
        {'1.0', '2.0', '2.5', '3.0', '4.0'}.contains(parts[2]);
    final cc0 =
        parts.length >= 3 &&
        parts[0] == 'publicdomain' &&
        parts[1] == 'zero' &&
        parts[2] == '1.0';
    final short = parts.length >= 2 && parts[0] == 'licenses'
        ? 'CC ${parts[1].toUpperCase()} ${parts.length > 2 ? parts[2] : ''}'
        : cc0
        ? 'CC0 1.0'
        : 'Лицензия требует проверки';
    final artist = '${j['artist_name'] ?? ''}'.trim();
    final source = Uri.https('www.jamendo.com', '/track/$id');
    final musicInfo = j['musicinfo'];
    final tags = musicInfo is Map ? musicInfo['tags'] : null;
    final genres = tags is Map ? tags['genres'] : null;
    final downloaded = j['audiodownload_allowed'] == true;
    final attribution =
        '«${title.trim()}» — $artist. $source\n$short${license == null ? '' : ': $license'}';
    return OnlineMusicTrack(
      id: id,
      title: title.trim(),
      artist: artist,
      genre: genres is List
          ? genres.whereType<String>().take(5).join(', ')
          : '',
      duration: Duration(milliseconds: (seconds * 1000).round()),
      previewUrl: preview,
      downloadUrl: downloaded ? audio('audiodownload') : null,
      sourceUrl: source,
      license: MusicLicense(
        name: short,
        attribution: attribution,
        url: license,
        downloadAllowed: downloaded,
        synchronizationAllowed: by || cc0,
        offlineAllowed: editingApproved && (by || cc0),
      ),
    );
  }

  Future<Map<String, dynamic>> _json(Map<String, String> parameters) async {
    if (unavailableReason != null) throw JamendoException(unavailableReason!);
    Map<String, dynamic> value;
    if (getJson != null) {
      value = await getJson!(parameters);
    } else {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 15);
      try {
        value = await (() async {
          final uri = Uri.https('api.jamendo.com', '/v3.0/tracks/', {
            'client_id': clientId,
            'format': 'json',
            ...parameters,
          });
          final request = await client.getUrl(uri);
          request.followRedirects = false;
          request.headers.set(
            HttpHeaders.userAgentHeader,
            'TigerVideoEdit/3.0 (+https://github.com/Flory211/tiger-video-edit)',
          );
          final response = await request.close();
          if (response.statusCode == 429) {
            throw const JamendoException(
              'Лимит Jamendo исчерпан. Попробуй позже.',
            );
          }
          if (response.statusCode != 200) {
            throw const JamendoException(
              'Jamendo временно недоступен. Повтори поиск позже.',
            );
          }
          final bytes = <int>[];
          await for (final chunk in response.timeout(
            const Duration(seconds: 15),
          )) {
            bytes.addAll(chunk);
            if (bytes.length > 3 * 1024 * 1024) {
              throw const JamendoException('Слишком большой ответ Jamendo.');
            }
          }
          return Map<String, dynamic>.from(
            jsonDecode(utf8.decode(bytes)) as Map,
          );
        })().timeout(const Duration(seconds: 25));
      } on JamendoException {
        rethrow;
      } on TimeoutException {
        throw const JamendoException(
          'Jamendo не отвечает. Проверь интернет и повтори поиск.',
        );
      } catch (_) {
        throw const JamendoException(
          'Не удалось связаться с Jamendo. Проверь интернет и Client ID.',
        );
      } finally {
        client.close(force: true);
      }
    }
    final header = value['headers'];
    if (header is! Map ||
        header['status'] != 'success' ||
        value['results'] is! List) {
      throw const JamendoException(
        'Jamendo отклонил запрос. Проверь Client ID или повтори позже.',
      );
    }
    return value;
  }

  Future<JamendoPage> searchPage(
    String query, {
    String genre = '',
    int page = 1,
    String sort = 'relevance',
    bool diverseArtists = false,
  }) async {
    if (page < 1 || page > 50) throw ArgumentError.value(page, 'page');
    if (!sorts.containsKey(sort)) throw ArgumentError.value(sort, 'sort');
    final text = query.trim();
    if (text.length > 200 || genre.length > 40) {
      throw const JamendoException('Слишком длинный поисковый запрос.');
    }
    // Jamendo's general search can miss "phonk". Match this keyword in
    // titles and combine it with the requested subtype instead of a broad tag.
    final (searchText, titleText) = switch (text.toLowerCase().replaceAll(
      RegExp(r'\s+'),
      ' ',
    )) {
      'phonk' || 'фонк' => (null, 'phonk'),
      'drift phonk' || 'дрифт фонк' || 'дрифт-фонк' => ('drift', 'phonk'),
      'brazilian phonk' || 'бразильский фонк' => ('brazilian', 'phonk'),
      'brazilian funk' || 'бразильский фанк' => ('brazilian funk', null),
      'montagem' || 'монтажем' => (null, 'montagem'),
      _ => (text.isEmpty ? null : text, null),
    };
    final key = jsonEncode([
      searchText,
      titleText,
      genre,
      page,
      sort,
      diverseArtists,
    ]);
    final cached = _cache[key];
    if (cached != null &&
        DateTime.now().difference(cached.$1) < const Duration(minutes: 2)) {
      return cached.$2;
    }
    final json = await _json({
      'limit': '$pageSize',
      'offset': '${(page - 1) * pageSize}',
      'include': 'licenses musicinfo',
      'audioformat': 'mp32',
      'type': 'single albumtrack',
      'order': text.isEmpty && sort == 'relevance' ? 'popularity_total' : sort,
      'search': ?searchText,
      'namesearch': ?titleText,
      if (genre.isNotEmpty) 'tags': genre,
      if (diverseArtists) 'groupby': 'artist_id',
    });
    final rows = json['results'] as List;
    final tracks = <OnlineMusicTrack>[];
    for (final item in rows.take(pageSize)) {
      if (item is! Map) continue;
      final track = parseTrack(
        Map<String, dynamic>.from(item),
        editingApproved: editingApproved,
      );
      if (track != null) tracks.add(track);
    }
    final result = JamendoPage(
      List.unmodifiable(tracks),
      hasMore: rows.length == pageSize && page < 50,
    );
    if (_cache.length >= 8) _cache.remove(_cache.keys.first);
    _cache[key] = (DateTime.now(), result);
    return result;
  }

  @override
  Future<List<OnlineMusicTrack>> search(String query, {String? genre}) async =>
      (await searchPage(query, genre: genre ?? '')).tracks;

  Future<OnlineMusicTrack> refresh(OnlineMusicTrack track) async {
    if (!RegExp(r'^\d{1,20}$').hasMatch(track.id)) {
      throw const JamendoException('Неверный трек.');
    }
    final response = await _json({
      'id': track.id,
      'limit': '1',
      'audioformat': 'mp32',
      'include': 'licenses musicinfo',
      'type': 'single albumtrack',
    });
    final rows = response['results'] as List;
    final fresh = rows.length == 1 && rows.first is Map
        ? parseTrack(
            Map<String, dynamic>.from(rows.first),
            editingApproved: editingApproved,
          )
        : null;
    if (fresh == null || fresh.id != track.id) {
      throw const JamendoException('Трек больше недоступен в Jamendo.');
    }
    return fresh;
  }

  Future<OnlineMusicTrack> _verified(OnlineMusicTrack track) async {
    if (!editingApproved) {
      throw const JamendoException(
        'Добавление из Jamendo в монтаж ожидает подтверждения условий сервиса. Поиск и прослушивание доступны.',
      );
    }
    final fresh = await refresh(track);
    if (!fresh.canDownload) {
      throw const JamendoException(
        'Автор или лицензия не разрешают добавление этого трека в монтаж.',
      );
    }
    return fresh;
  }

  @override
  Future<Stream<List<int>>> download(OnlineMusicTrack track) async {
    final fresh = await _verified(track);
    return _bytes(fresh.downloadUrl!);
  }

  Future<JamendoPreview> openPreview(OnlineMusicTrack track) async {
    final fresh = await refresh(track);
    return JamendoPreview.start(
      fresh,
      (register) =>
          audioStream?.call(fresh.previewUrl!) ??
          _audioBytes(fresh.previewUrl!, onClient: register),
    );
  }

  Stream<List<int>> _bytes(Uri uri) =>
      audioStream?.call(uri) ?? _audioBytes(uri);

  Stream<List<int>> _audioBytes(
    Uri start, {
    void Function(HttpClient)? onClient,
  }) async* {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    onClient?.call(client);
    try {
      var uri = start;
      for (var redirects = 0; redirects <= 3; redirects++) {
        if (!safeAudio(uri)) {
          throw const JamendoException('Небезопасный адрес аудио.');
        }
        final request = await client
            .getUrl(uri)
            .timeout(const Duration(seconds: 15));
        request.followRedirects = false;
        final response = await request.close().timeout(
          const Duration(seconds: 15),
        );
        if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          if (location == null) break;
          uri = uri.resolve(location);
          continue;
        }
        if (response.statusCode != 200) break;
        var size = 0;
        await for (final bytes in response.timeout(
          const Duration(seconds: 15),
        )) {
          size += bytes.length;
          if (size > 128 * 1024 * 1024) {
            throw const JamendoException('Трек превышает 128 МБ.');
          }
          yield bytes;
        }
        if (size == 0) {
          throw const JamendoException('Получен пустой аудиофайл.');
        }
        return;
      }
      throw const JamendoException('Не удалось загрузить аудио Jamendo.');
    } on JamendoException {
      rethrow;
    } catch (_) {
      throw const JamendoException(
        'Загрузка Jamendo прервана. Проверь интернет.',
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<(File, OnlineMusicTrack)> prepareForEditing(
    OnlineMusicTrack track,
    Directory directory, {
    void Function(int bytes)? onProgress,
    bool Function()? cancelled,
  }) async {
    final fresh = await _verified(track);
    if (cancelled?.call() == true) {
      throw const JamendoException('Загрузка отменена.');
    }
    await directory.create(recursive: true);
    final file = File(
      '${directory.path}/jamendo-${fresh.id}-${DateTime.now().microsecondsSinceEpoch}.mp3',
    );
    final stage = File('${file.path}.part');
    final sink = stage.openWrite();
    try {
      var total = 0;
      final elapsed = Stopwatch()..start();
      await for (final chunk in _bytes(
        fresh.downloadUrl!,
      ).timeout(const Duration(seconds: 120))) {
        if (cancelled?.call() == true) {
          throw const JamendoException('Загрузка отменена.');
        }
        if (elapsed.elapsed > const Duration(minutes: 2) ||
            total + chunk.length > 128 * 1024 * 1024) {
          throw const JamendoException(
            'Превышен лимит времени или размера трека.',
          );
        }
        sink.add(chunk);
        total += chunk.length;
        onProgress?.call(total);
      }
      await sink.flush();
      await sink.close();
      if (total == 0) throw const JamendoException('Получен пустой аудиофайл.');
      if (cancelled?.call() == true) {
        throw const JamendoException('Загрузка отменена.');
      }
      await stage.rename(file.path);
      return (file, fresh);
    } catch (_) {
      await sink.close();
      if (await file.exists()) await file.delete();
      rethrow;
    } finally {
      if (await stage.exists()) await stage.delete();
    }
  }
}
