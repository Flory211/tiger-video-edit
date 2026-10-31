import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

import 'app_settings.dart';

class SemanticVersion implements Comparable<SemanticVersion> {
  final int major, minor, patch;
  final List<String> prerelease;
  const SemanticVersion(
    this.major,
    this.minor,
    this.patch, [
    this.prerelease = const [],
  ]);
  factory SemanticVersion.parse(String value) {
    final match = RegExp(
      r'^v?(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$',
    ).firstMatch(value);
    if (match == null) throw FormatException('Invalid semantic version', value);
    final pre = match[4]?.split('.') ?? <String>[];
    if (pre.any((p) => RegExp(r'^0\d+$').hasMatch(p))) {
      throw FormatException('Leading zero in prerelease', value);
    }
    return SemanticVersion(
      int.parse(match[1]!),
      int.parse(match[2]!),
      int.parse(match[3]!),
      List.unmodifiable(pre),
    );
  }
  @override
  int compareTo(SemanticVersion other) {
    for (final pair in [
      (major, other.major),
      (minor, other.minor),
      (patch, other.patch),
    ]) {
      final c = pair.$1.compareTo(pair.$2);
      if (c != 0) return c;
    }
    if (prerelease.isEmpty || other.prerelease.isEmpty) {
      return prerelease.isEmpty == other.prerelease.isEmpty
          ? 0
          : prerelease.isEmpty
          ? 1
          : -1;
    }
    for (var i = 0; i < prerelease.length && i < other.prerelease.length; i++) {
      final a = prerelease[i], b = other.prerelease[i];
      final an = int.tryParse(a), bn = int.tryParse(b);
      final c = an != null && bn != null
          ? an.compareTo(bn)
          : an != null
          ? -1
          : bn != null
          ? 1
          : a.compareTo(b);
      if (c != 0) return c;
    }
    return prerelease.length.compareTo(other.prerelease.length);
  }

  bool operator >(SemanticVersion other) => compareTo(other) > 0;
  @override
  String toString() =>
      '$major.$minor.$patch${prerelease.isEmpty ? '' : '-${prerelease.join('.')}'}';
}

enum UpdatePlatform { windowsX64, androidArm64 }

enum UpdateStatus {
  available,
  upToDate,
  notConfigured,
  noCompatibleAsset,
  offline,
  timedOut,
  rateLimited,
  invalidResponse,
  serverError,
}

class UpdateException implements Exception {
  final String message;
  const UpdateException(this.message);
  @override
  String toString() => message;
}

class UpdateAsset {
  final String name;
  final Uri url;
  final int size;
  final String? sha256;
  final Uri? checksumUrl;
  const UpdateAsset({
    required this.name,
    required this.url,
    required this.size,
    this.sha256,
    this.checksumUrl,
  });
}

class UpdateRelease {
  final SemanticVersion version;
  final String tag, notes;
  final Uri pageUrl;
  final List<UpdateAsset> assets;
  const UpdateRelease({
    required this.version,
    required this.tag,
    required this.notes,
    required this.pageUrl,
    required this.assets,
  });
}

class UpdateCheck {
  final UpdateStatus status;
  final UpdateRelease? release;
  final UpdateAsset? asset;
  final String message;
  final bool fromCache;
  const UpdateCheck(
    this.status, {
    this.release,
    this.asset,
    this.message = '',
    this.fromCache = false,
  });
}

class DownloadCancellation {
  final Completer<void> _cancelled = Completer<void>();
  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;
  void cancel() {
    if (!isCancelled) _cancelled.complete();
  }

  void throwIfCancelled() {
    if (isCancelled) throw const UpdateException('Download cancelled');
  }
}

class UpdateResponse {
  final int statusCode;
  final Stream<List<int>> body;
  const UpdateResponse(this.statusCode, this.body);
}

abstract interface class UpdateTransport {
  Future<UpdateResponse> get(Uri uri, {Map<String, String> headers = const {}});
}

bool _safeHttps(Uri uri) =>
    uri.scheme == 'https' &&
    uri.userInfo.isEmpty &&
    (!uri.hasPort || uri.port == 443) &&
    uri.fragment.isEmpty;

/// No credentials, cookies, automatic browser redirects or private API tokens.
/// Redirects are restricted to GitHub's release asset delivery hosts.
class IoUpdateTransport implements UpdateTransport {
  final Duration timeout;
  const IoUpdateTransport({this.timeout = const Duration(seconds: 20)});
  @override
  Future<UpdateResponse> get(
    Uri uri, {
    Map<String, String> headers = const {},
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      var target = uri;
      for (var redirects = 0; redirects <= 5; redirects++) {
        if (!_safeHttps(target) ||
            !{
              'api.github.com',
              'github.com',
              'release-assets.githubusercontent.com',
              'objects.githubusercontent.com',
            }.contains(target.host)) {
          throw const UpdateException('Untrusted update host');
        }
        final request = await client.getUrl(target).timeout(timeout);
        request.followRedirects = false;
        request.headers.set(
          HttpHeaders.userAgentHeader,
          'TigerVideoEdit-Updater/3',
        );
        headers.forEach(request.headers.set);
        final response = await request.close().timeout(timeout);
        if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          await response.drain<void>().timeout(timeout);
          if (location == null || uri.host == 'api.github.com') {
            throw const UpdateException('Unexpected update redirect');
          }
          target = target.resolve(location);
          continue;
        }
        return UpdateResponse(
          response.statusCode,
          (() async* {
            try {
              yield* response.timeout(timeout);
            } finally {
              client.close(force: true);
            }
          })(),
        );
      }
      throw const UpdateException('Too many update redirects');
    } catch (_) {
      client.close(force: true);
      rethrow;
    }
  }
}

class UpdateService {
  final String owner, repository;
  final File cacheFile;
  final UpdateTransport transport;
  final Duration timeout;
  final DateTime Function() now;
  bool _downloading = false;
  UpdateService({
    this.owner = const String.fromEnvironment('TVE_GITHUB_OWNER'),
    this.repository = const String.fromEnvironment(
      'TVE_GITHUB_REPO',
      defaultValue: 'TigerVideoEdit',
    ),
    required this.cacheFile,
    UpdateTransport? transport,
    this.timeout = const Duration(seconds: 20),
    DateTime Function()? now,
  }) : transport = transport ?? IoUpdateTransport(timeout: timeout),
       now = now ?? DateTime.now;

  bool get configured =>
      RegExp(r'^[A-Za-z0-9][A-Za-z0-9-]{0,38}$').hasMatch(owner) &&
      RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(repository) &&
      repository != '.' &&
      repository != '..';
  String get configurationMessage => configured
      ? '$owner/$repository'
      : 'Public releases are not configured. Build with TVE_GITHUB_OWNER and TVE_GITHUB_REPO.';

  File get _attemptFile => File('${cacheFile.path}.attempt.json');
  static const _failureStatuses = {
    UpdateStatus.offline,
    UpdateStatus.timedOut,
    UpdateStatus.rateLimited,
    UpdateStatus.invalidResponse,
    UpdateStatus.serverError,
  };

  Future<UpdateCheck?> _cachedFailure(
    String version,
    UpdatePlatform platform,
  ) async {
    try {
      if (await _attemptFile.length() > 32768) return null;
      final data =
          jsonDecode(await _attemptFile.readAsString()) as Map<String, dynamic>;
      final age = now().toUtc().difference(
        DateTime.parse(data['checkedAt'] as String),
      );
      final status = _failureStatuses
          .where((s) => s.name == data['status'])
          .firstOrNull;
      if (data['repository'] == '$owner/$repository' &&
          data['platform'] == platform.name &&
          data['currentVersion'] == version &&
          !age.isNegative &&
          age < const Duration(hours: 1) &&
          status != null &&
          data['message'] is String) {
        return UpdateCheck(
          status,
          message: data['message'] as String,
          fromCache: true,
        );
      }
    } on FileSystemException {
      /* No writable/valid attempt metadata. */
    } on FormatException {
      /* Ignore malformed metadata. */
    } on TypeError {
      /* Ignore malformed metadata. */
    }
    return null;
  }

  Future<UpdateCheck> _rememberFailure(
    UpdateCheck result,
    String version,
    UpdatePlatform platform,
  ) async {
    try {
      await atomicWriteBytes(
        _attemptFile,
        utf8.encode(
          jsonEncode({
            'repository': '$owner/$repository',
            'platform': platform.name,
            'currentVersion': version,
            'checkedAt': now().toUtc().toIso8601String(),
            'status': result.status.name,
            'message': result.message,
          }),
        ),
      );
    } on FileSystemException {
      /* A read-only cache must not hide the real error. */
    }
    return result;
  }

  Future<void> _clearFailure() async {
    for (final file in [_attemptFile, File('${_attemptFile.path}.bak')]) {
      try {
        if (await file.exists()) await file.delete();
      } on FileSystemException {
        /* Best-effort metadata cleanup. */
      }
    }
  }

  bool _trustedAsset(Uri uri) {
    if (!_safeHttps(uri) || uri.host != 'github.com' || uri.hasQuery) {
      return false;
    }
    final segments = uri.pathSegments;
    return segments.length == 6 &&
        segments[0].toLowerCase() == owner.toLowerCase() &&
        segments[1].toLowerCase() == repository.toLowerCase() &&
        segments[2] == 'releases' &&
        segments[3] == 'download' &&
        segments[4].isNotEmpty &&
        segments[5].isNotEmpty &&
        !segments.any(
          (part) =>
              part == '.' ||
              part == '..' ||
              part.contains('/') ||
              part.contains('\\'),
        );
  }

  Future<UpdateCheck> check({
    required String currentVersion,
    required UpdatePlatform platform,
    bool force = false,
  }) async {
    if (!configured) {
      return UpdateCheck(
        UpdateStatus.notConfigured,
        message: configurationMessage,
      );
    }
    try {
      final installed = SemanticVersion.parse(currentVersion);
      if (!force) {
        try {
          if (await cacheFile.length() <= 2 * 1024 * 1024) {
            final cache = jsonDecode(
              await cacheFile.readAsString(),
            ) as Map<String, dynamic>;
            final age = now().toUtc().difference(
              DateTime.parse(cache['checkedAt'] as String),
            );
            if (cache['repository'] == '$owner/$repository' &&
                !age.isNegative &&
                age < const Duration(hours: 24)) {
              return _evaluate(
                cache['releases'] as List,
                installed,
                platform,
                fromCache: true,
              );
            }
          }
        } on FileSystemException {
          /* No cache. */
        } on FormatException {
          /* Refetch. */
        } on TypeError {
          /* Refetch. */
        }
        final failure = await _cachedFailure(currentVersion, platform);
        if (failure != null) return failure;
      }
      final uri = Uri.https(
        'api.github.com',
        '/repos/$owner/$repository/releases',
        {'per_page': '100'},
      );
      final response = await transport
          .get(
            uri,
            headers: {
              'Accept': 'application/vnd.github+json',
              'X-GitHub-Api-Version': '2022-11-28',
            },
          )
          .timeout(timeout);
      final bytes = await _readBounded(response.body, 2 * 1024 * 1024);
      if (response.statusCode == 403 || response.statusCode == 429) {
        return await _rememberFailure(
          const UpdateCheck(
            UpdateStatus.rateLimited,
            message: 'GitHub request limit reached. Try later.',
          ),
          currentVersion,
          platform,
        );
      }
      if (response.statusCode != 200) {
        return await _rememberFailure(
          UpdateCheck(
            UpdateStatus.serverError,
            message: 'Public releases returned HTTP ${response.statusCode}.',
          ),
          currentVersion,
          platform,
        );
      }
      final releases = jsonDecode(utf8.decode(bytes)) as List;
      final result = _evaluate(releases, installed, platform);
      // Cache only a structurally valid response; network failures never poison it.
      if (result.status != UpdateStatus.invalidResponse) {
        await _clearFailure();
        try {
          await atomicWriteBytes(
            cacheFile,
            utf8.encode(
              jsonEncode({
                'repository': '$owner/$repository',
                'checkedAt': now().toUtc().toIso8601String(),
                'releases': releases,
              }),
            ),
          );
        } on FileSystemException {
          /* Read-only cache must not hide an update. */
        }
      }
      return result;
    } on TimeoutException {
      return _rememberFailure(
        const UpdateCheck(
          UpdateStatus.timedOut,
          message: 'Update check timed out.',
        ),
        currentVersion,
        platform,
      );
    } on SocketException {
      return _rememberFailure(
        const UpdateCheck(
          UpdateStatus.offline,
          message: 'No connection to GitHub.',
        ),
        currentVersion,
        platform,
      );
    } on HandshakeException {
      return _rememberFailure(
        const UpdateCheck(
          UpdateStatus.offline,
          message: 'A secure GitHub connection could not be established.',
        ),
        currentVersion,
        platform,
      );
    } on FormatException {
      return _rememberFailure(
        const UpdateCheck(
          UpdateStatus.invalidResponse,
          message: 'Invalid release or version data.',
        ),
        currentVersion,
        platform,
      );
    } on TypeError {
      return _rememberFailure(
        const UpdateCheck(
          UpdateStatus.invalidResponse,
          message: 'Invalid GitHub release response.',
        ),
        currentVersion,
        platform,
      );
    } on UpdateException catch (e) {
      return _rememberFailure(
        UpdateCheck(UpdateStatus.invalidResponse, message: e.message),
        currentVersion,
        platform,
      );
    } on HttpException {
      return _rememberFailure(
        const UpdateCheck(
          UpdateStatus.offline,
          message: 'Connection to GitHub was interrupted.',
        ),
        currentVersion,
        platform,
      );
    }
  }

  UpdateCheck _evaluate(
    List data,
    SemanticVersion installed,
    UpdatePlatform platform, {
    bool fromCache = false,
  }) {
    final releases = <UpdateRelease>[];
    for (final entry in data) {
      if (entry is! Map<String, dynamic>) {
        throw const FormatException('Invalid release');
      }
      if (entry['draft'] == true || entry['prerelease'] == true) continue;
      final tag = entry['tag_name'] as String;
      SemanticVersion version;
      try {
        version = SemanticVersion.parse(tag);
      } on FormatException {
        continue;
      }
      if (version.prerelease.isNotEmpty) continue;
      final raw = entry['assets'] as List;
      final assets = <UpdateAsset>[];
      for (final value in raw) {
        final asset = value as Map<String, dynamic>;
        final url = Uri.parse(asset['browser_download_url'] as String);
        final name = asset['name'] as String;
        final size = (asset['size'] as num).toInt();
        if (!_trustedAsset(url) ||
            url.pathSegments[4] != tag ||
            url.pathSegments.last != name ||
            size <= 0 ||
            size > 2 * 1024 * 1024 * 1024) {
          continue;
        }
        final digest = asset['digest'] as String?;
        final hash =
            digest != null &&
                RegExp(r'^sha256:[a-fA-F0-9]{64}$').hasMatch(digest)
            ? digest.substring(7).toLowerCase()
            : null;
        assets.add(UpdateAsset(name: name, url: url, size: size, sha256: hash));
      }
      releases.add(
        UpdateRelease(
          version: version,
          tag: tag,
          notes: entry['body'] as String? ?? '',
          pageUrl: Uri.https(
            'github.com',
            '/$owner/$repository/releases/tag/$tag',
          ),
          assets: assets,
        ),
      );
    }
    releases.sort((a, b) => b.version.compareTo(a.version));
    final newer = releases.where((r) => r.version > installed).toList();
    for (final release in newer) {
      for (final asset in release.assets) {
        if (!_compatible(asset.name, platform)) continue;
        final checksum = release.assets
            .where(
              (a) =>
                  a.name == '${asset.name}.sha256' ||
                  [
                    'sha256sums',
                    'sha256sums.txt',
                    'checksums.sha256',
                  ].contains(a.name.toLowerCase()),
            )
            .firstOrNull;
        if (asset.sha256 == null && checksum == null) continue;
        return UpdateCheck(
          UpdateStatus.available,
          release: release,
          fromCache: fromCache,
          asset: UpdateAsset(
            name: asset.name,
            url: asset.url,
            size: asset.size,
            sha256: asset.sha256,
            checksumUrl: checksum?.url,
          ),
        );
      }
    }
    return UpdateCheck(
      newer.isEmpty ? UpdateStatus.upToDate : UpdateStatus.noCompatibleAsset,
      fromCache: fromCache,
      message: newer.isEmpty
          ? 'Latest compatible version is installed.'
          : 'No compatible installer with a SHA-256 checksum is published.',
    );
  }

  bool _compatible(String name, UpdatePlatform platform) {
    final n = name.toLowerCase();
    if (n.contains('debug') || n.contains('unsigned')) return false;
    return switch (platform) {
      UpdatePlatform.windowsX64 =>
        n.endsWith('.exe') &&
            n.contains('windows') &&
            (n.contains('x64') || n.contains('amd64')) &&
            (n.contains('setup') || n.contains('installer')),
      UpdatePlatform.androidArm64 =>
        n.endsWith('.apk') &&
            n.contains('android') &&
            (n.contains('arm64') || n.contains('aarch64')),
    };
  }

  Future<List<int>> _readBounded(
    Stream<List<int>> stream,
    int maximum, {
    DownloadCancellation? cancellation,
  }) async {
    final bytes = <int>[];
    final iterator = StreamIterator(stream.timeout(timeout));
    try {
      while (await _moveNext(iterator, cancellation)) {
        if (bytes.length + iterator.current.length > maximum) {
          throw const UpdateException('Response exceeds size limit');
        }
        bytes.addAll(iterator.current);
      }
    } finally {
      await iterator.cancel();
    }
    return bytes;
  }

  Future<bool> _moveNext(
    StreamIterator<List<int>> iterator,
    DownloadCancellation? cancellation,
  ) {
    cancellation?.throwIfCancelled();
    return cancellation == null
        ? iterator.moveNext()
        : Future.any([
            iterator.moveNext(),
            cancellation.whenCancelled.then<bool>(
              (_) => throw const UpdateException('Download cancelled'),
            ),
          ]);
  }

  /// Returns a verified local installer. Never starts it or requests elevation.
  /// Existing destination survives cancellation, hash mismatch or network error.
  Future<File> download(
    UpdateAsset asset,
    File destination, {
    DownloadCancellation? cancellation,
    void Function(int received, int total)? onProgress,
  }) async {
    if (_downloading) {
      throw const UpdateException('An update download is already active');
    }
    if (!configured ||
        !_trustedAsset(asset.url) ||
        asset.url.pathSegments.last != asset.name ||
        asset.size <= 0 ||
        asset.size > 2 * 1024 * 1024 * 1024) {
      throw const UpdateException('Untrusted installer asset');
    }
    _downloading = true;
    File? stage;
    try {
      cancellation?.throwIfCancelled();
      var expectedHash = asset.sha256;
      if (expectedHash == null) {
        final checksumUrl = asset.checksumUrl;
        if (checksumUrl == null ||
            !_trustedAsset(checksumUrl) ||
            checksumUrl.pathSegments[4] != asset.url.pathSegments[4]) {
          throw const UpdateException('Missing trusted SHA-256 checksum');
        }
        final response = await transport.get(checksumUrl).timeout(timeout);
        final bytes = await _readBounded(
          response.body,
          256 * 1024,
          cancellation: cancellation,
        );
        if (response.statusCode != 200) {
          throw const UpdateException('Checksum download failed');
        }
        expectedHash = _checksumFor(
          utf8.decode(bytes),
          asset.name,
          singleFile: checksumUrl.pathSegments.last == '${asset.name}.sha256',
        );
      }
      if (!RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(expectedHash)) {
        throw const UpdateException('Invalid SHA-256 checksum');
      }
      cancellation?.throwIfCancelled();
      await destination.parent.create(recursive: true);
      stage = File('${destination.path}.${now().microsecondsSinceEpoch}.part');
      final response = await transport.get(asset.url).timeout(timeout);
      final iterator = StreamIterator(response.body.timeout(timeout));
      final output = stage.openWrite();
      var count = 0;
      try {
        if (response.statusCode != 200) {
          throw UpdateException(
            'Installer download returned HTTP ${response.statusCode}',
          );
        }
        while (await _moveNext(iterator, cancellation)) {
          count += iterator.current.length;
          if (count > asset.size) {
            throw const UpdateException('Installer exceeds its published size');
          }
          output.add(iterator.current);
          // Bound the sink queue even when the network is faster than storage.
          await output.flush();
          onProgress?.call(count, asset.size);
        }
        await output.flush();
      } finally {
        await iterator.cancel();
        await output.close();
      }
      cancellation?.throwIfCancelled();
      if (count != asset.size) {
        throw const UpdateException('Incomplete installer download');
      }
      final actualHash = await crypto.sha256.bind(stage.openRead()).first;
      if (actualHash.toString() != expectedHash.toLowerCase()) {
        throw const UpdateException('Installer SHA-256 verification failed');
      }
      cancellation?.throwIfCancelled();
      await replaceStagedFile(stage, destination);
      return destination;
    } finally {
      _downloading = false;
      if (stage != null && await stage.exists()) await stage.delete();
    }
  }

  String _checksumFor(String text, String name, {required bool singleFile}) {
    final hashes = <String>[];
    for (final line in const LineSplitter().convert(text)) {
      final match = RegExp(r'^([a-fA-F0-9]{64})(?:\s+\*?(.+))?$')
          .firstMatch(line.trim());
      if (match != null &&
          ((singleFile && match[2] == null) || match[2] == name)) {
        hashes.add(match[1]!);
      }
    }
    if (hashes.length != 1) {
      throw const UpdateException(
        'Checksum file has no unique matching installer entry',
      );
    }
    return hashes.single.toLowerCase();
  }
}
