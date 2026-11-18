import 'dart:convert';
import 'dart:io';

import 'app_settings.dart';

class MusicLicense {
  final String name, attribution;
  final Uri? url;
  final bool downloadAllowed, offlineAllowed, synchronizationAllowed;
  const MusicLicense({
    this.name = 'User supplied — verify usage rights',
    this.attribution = '',
    this.url,
    this.downloadAllowed = false,
    this.offlineAllowed = false,
    this.synchronizationAllowed = false,
  });

  bool get permitsEditorDownload =>
      downloadAllowed && offlineAllowed && synchronizationAllowed;
  Map<String, dynamic> toJson() => {
    'name': name,
    'attribution': attribution,
    'url': url?.toString(),
    'downloadAllowed': downloadAllowed,
    'offlineAllowed': offlineAllowed,
    'synchronizationAllowed': synchronizationAllowed,
  };
  factory MusicLicense.fromJson(Map<String, dynamic> json) => MusicLicense(
    name: json['name'] as String? ?? 'Unknown rights',
    attribution: json['attribution'] as String? ?? '',
    url: Uri.tryParse(json['url'] as String? ?? ''),
    downloadAllowed: json['downloadAllowed'] == true,
    offlineAllowed: json['offlineAllowed'] == true,
    synchronizationAllowed: json['synchronizationAllowed'] == true,
  );
}

class MusicTrack {
  final String id, title, artist, genre, path;
  final Duration duration;
  final MusicLicense license;
  final DateTime importedAt;
  final String? providerId;
  const MusicTrack({
    required this.id,
    required this.title,
    required this.path,
    this.artist = '',
    this.genre = '',
    this.duration = Duration.zero,
    this.license = const MusicLicense(),
    required this.importedAt,
    this.providerId,
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    'genre': genre,
    'path': path,
    'durationMs': duration.inMilliseconds,
    'license': license.toJson(),
    'importedAt': importedAt.toUtc().toIso8601String(),
    'providerId': providerId,
  };
  factory MusicTrack.fromJson(Map<String, dynamic> json) => MusicTrack(
    id: json['id'] as String,
    title: json['title'] as String,
    path: json['path'] as String,
    artist: json['artist'] as String? ?? '',
    genre: json['genre'] as String? ?? '',
    duration: Duration(
      milliseconds: (json['durationMs'] as num? ?? 0).toInt().clamp(
        0,
        86400000,
      ),
    ),
    license: MusicLicense.fromJson(
      json['license'] as Map<String, dynamic>? ?? {},
    ),
    importedAt: DateTime.parse(json['importedAt'] as String),
    providerId: json['providerId'] as String?,
  );
}

class OnlineMusicTrack {
  final String id, title, artist, genre;
  final Duration duration;
  final Uri? previewUrl, downloadUrl, sourceUrl;
  final MusicLicense license;
  const OnlineMusicTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.duration,
    required this.license,
    this.genre = '',
    this.previewUrl,
    this.downloadUrl,
    this.sourceUrl,
  });
  bool get canDownload =>
      license.permitsEditorDownload &&
      downloadUrl?.scheme == 'https' &&
      downloadUrl?.userInfo == '';

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    'genre': genre,
    'durationMs': duration.inMilliseconds,
    'license': license.toJson(),
    'previewUrl': previewUrl?.toString(),
    'downloadUrl': downloadUrl?.toString(),
    'sourceUrl': sourceUrl?.toString(),
  };
  factory OnlineMusicTrack.fromJson(Map<String, dynamic> j) => OnlineMusicTrack(
    id: j['id'] as String,
    title: j['title'] as String,
    artist: j['artist'] as String,
    genre: j['genre'] as String? ?? '',
    duration: Duration(milliseconds: j['durationMs'] as int),
    license: MusicLicense.fromJson(
      Map<String, dynamic>.from(j['license'] as Map),
    ),
    previewUrl: Uri.tryParse(j['previewUrl'] as String? ?? ''),
    downloadUrl: Uri.tryParse(j['downloadUrl'] as String? ?? ''),
    sourceUrl: Uri.tryParse(j['sourceUrl'] as String? ?? ''),
  );
}

/// Implementations must have a documented application agreement and must not
/// equate a stream URL or a free download with video synchronization rights.
abstract interface class OnlineMusicProvider {
  String get id;
  String get displayName;
  String? get unavailableReason;
  Future<List<OnlineMusicTrack>> search(String query, {String? genre});
  Future<Stream<List<int>>> download(OnlineMusicTrack track);
}

class MusicSources {
  static const jamendoUnavailableReasonRu =
      'Локальная музыка доступна офлайн. Онлайн-каталог Jamendo пока не подключён: '
      'нужны соглашение для офлайн-загрузки и синхронизации с видео, а также Client ID.';
  static const jamendoUnavailableReason =
      'Jamendo requires an approved application agreement covering offline '
      'downloads and video synchronization, plus a registered client ID. '
      'No provider is enabled. Import your licensed local music.';
}

class MusicLibrary {
  final Directory root;
  final List<MusicTrack> _tracks = [];
  final Set<String> _favorites = {};
  final List<String> _history = [];
  Future<void> _pending = Future.value();
  MusicLibrary(this.root);
  List<MusicTrack> get tracks => List.unmodifiable(_tracks);
  Set<String> get favorites => Set.unmodifiable(_favorites);
  List<String> get history => List.unmodifiable(_history);
  File get _catalog => File('${root.path}/catalog.json');

  Future<void> load() async {
    await root.create(recursive: true);
    for (final file in [_catalog, File('${_catalog.path}.bak')]) {
      try {
        if (await file.length() > 8 * 1024 * 1024) continue;
        final json =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final tracks = (json['tracks'] as List)
            .map((e) => MusicTrack.fromJson(e as Map<String, dynamic>))
            .toList();
        _tracks
          ..clear()
          ..addAll(tracks);
        _favorites
          ..clear()
          ..addAll(
            (json['favorites'] as List? ?? []).whereType<String>().where(
              (id) => tracks.any((t) => t.id == id),
            ),
          );
        _history
          ..clear()
          ..addAll(
            (json['history'] as List? ?? [])
                .whereType<String>()
                .where((id) => tracks.any((t) => t.id == id))
                .take(100),
          );
        return;
      } on FileSystemException {
        continue;
      } on FormatException {
        continue;
      } on TypeError {
        continue;
      }
    }
    // A failed load never erases an in-memory catalog or its media files.
  }

  List<MusicTrack> search(
    String query, {
    String? genre,
    bool favoritesOnly = false,
  }) {
    final terms = query
        .toLowerCase()
        .trim()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty);
    return _tracks.where((track) {
      final text = '${track.title} ${track.artist} ${track.genre}'
          .toLowerCase();
      return terms.every(text.contains) &&
          (genre == null ||
              genre.isEmpty ||
              track.genre.toLowerCase() == genre.toLowerCase()) &&
          (!favoritesOnly || _favorites.contains(track.id));
    }).toList();
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = _pending.then((_) => operation());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<MusicTrack> importFile(
    String sourcePath, {
    String? title,
    String artist = '',
    String genre = '',
    Duration duration = Duration.zero,
    MusicLicense license = const MusicLicense(),
  }) => _serialize(() async {
    final source = File(sourcePath);
    final name = sourcePath.replaceAll('\\', '/').split('/').last;
    final extension = name.contains('.')
        ? name.split('.').last.toLowerCase()
        : '';
    if (![
      'mp3',
      'wav',
      'm4a',
      'aac',
      'ogg',
      'flac',
      'opus',
    ].contains(extension)) {
      throw const FormatException('Unsupported audio format');
    }
    final length = await source.length();
    if (length <= 0 || length > 1024 * 1024 * 1024) {
      throw const FormatException('Audio is empty or exceeds 1 GiB');
    }
    await Directory('${root.path}/audio').create(recursive: true);
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final destination = File('${root.path}/audio/$id.$extension');
    final stage = File('${destination.path}.tmp');
    try {
      await source.copy(stage.path);
      if (await stage.length() != length) {
        throw const FileSystemException('Incomplete audio copy');
      }
      await stage.rename(destination.path);
      final track = MusicTrack(
        id: id,
        title: title?.trim().isNotEmpty == true ? title!.trim() : name,
        path: destination.absolute.path,
        artist: artist,
        genre: genre,
        duration: duration.isNegative ? Duration.zero : duration,
        license: license,
        importedAt: DateTime.now(),
      );
      _tracks.add(track);
      try {
        await _save();
      } catch (_) {
        _tracks.remove(track);
        rethrow;
      }
      return track;
    } catch (_) {
      if (await destination.exists()) await destination.delete();
      rethrow;
    } finally {
      if (await stage.exists()) await stage.delete();
    }
  });

  Future<void> toggleFavorite(String id) => _serialize(() async {
    _requireTrack(id);
    final wasFavorite = _favorites.contains(id);
    if (wasFavorite) {
      _favorites.remove(id);
    } else {
      _favorites.add(id);
    }
    try {
      await _save();
    } catch (_) {
      if (wasFavorite) {
        _favorites.add(id);
      } else {
        _favorites.remove(id);
      }
      rethrow;
    }
  });

  Future<void> recordUse(String id) => _serialize(() async {
    _requireTrack(id);
    final previous = List<String>.of(_history);
    _history
      ..remove(id)
      ..insert(0, id);
    if (_history.length > 100) _history.removeRange(100, _history.length);
    try {
      await _save();
    } catch (_) {
      _history
        ..clear()
        ..addAll(previous);
      rethrow;
    }
  });

  void _requireTrack(String id) {
    if (!_tracks.any((track) => track.id == id)) {
      throw ArgumentError.value(id, 'id', 'Unknown music track');
    }
  }

  Future<void> _save() => atomicWriteBytes(
    _catalog,
    utf8.encode(
      jsonEncode({
        'schema': 1,
        'tracks': _tracks.map((t) => t.toJson()).toList(),
        'favorites': _favorites.toList(),
        'history': _history,
      }),
    ),
  );
}
