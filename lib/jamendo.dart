import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
  }) async {
    if (page < 1 || page > 50) throw ArgumentError.value(page, 'page');
    final text = query.trim();
    if (text.length > 200 || genre.length > 40) {
      throw const JamendoException('Слишком длинный поисковый запрос.');
    }
    final key = jsonEncode([text, genre, page]);
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
      'order': text.isEmpty ? 'popularity_total' : 'relevance',
      if (text.isNotEmpty) 'search': text,
      if (genre.isNotEmpty) 'tags': genre,
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

  Future<OnlineMusicTrack> _verified(OnlineMusicTrack track) async {
    if (!editingApproved) {
      throw const JamendoException(
        'Добавление из Jamendo в монтаж ожидает подтверждения условий сервиса. Поиск и прослушивание доступны.',
      );
    }
    if (!RegExp(r'^\d{1,20}$').hasMatch(track.id)) {
      throw const JamendoException('Неверный трек.');
    }
    final response = await _json({
      'id': track.id,
      'limit': '1',
      'audioformat': 'mp32',
      'include': 'licenses musicinfo',
    });
    final rows = response['results'] as List;
    final fresh = rows.length == 1 && rows.first is Map
        ? parseTrack(
            Map<String, dynamic>.from(rows.first),
            editingApproved: true,
          )
        : null;
    if (fresh == null || fresh.id != track.id || !fresh.canDownload) {
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

  Stream<List<int>> _bytes(Uri uri) =>
      audioStream?.call(uri) ?? _audioBytes(uri);

  Stream<List<int>> _audioBytes(Uri start) async* {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
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
