import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiger_video_edit/app_settings.dart';
import 'package:tiger_video_edit/music_library.dart';
import 'package:tiger_video_edit/sound_library.dart';
import 'package:tiger_video_edit/update_service.dart';

void main() {
  extraServiceTests();
  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('tve-services-');
  });
  tearDown(() async {
    await temp.delete(recursive: true);
  });

  test(
    'settings preserve preferences, clamp unsafe values and recover backup',
    () async {
      final store = SettingsStore(File('${temp.path}/settings.json'));
      final settings = const AppSettings().copyWith(
        theme: AppTheme.light,
        language: 'en',
        reducedMotion: true,
        previewVolume: 0.4,
        favoriteEffects: {'glow'},
        recentEffects: ['shake'],
        autoCheckUpdates: false,
      );
      await store.save(settings);
      expect((await store.load()).toJson(), settings.toJson());
      await store.save(settings.copyWith(language: 'ru'));
      await store.file.writeAsString('broken');
      expect((await store.load()).language, 'en');
      expect(AppSettings.fromJson({'previewVolume': 100}).previewVolume, 1);
      expect(settings.animationsAllowed(systemReducedMotion: true), false);
    },
  );

  test(
    'local import is copied, searchable, persisted with favorites and history',
    () async {
      final source = await File('${temp.path}/source.wav')
          .writeAsBytes([1, 2, 3]);
      final library = MusicLibrary(Directory('${temp.path}/music'));
      await library.load();
      final track = await library.importFile(
        source.path,
        title: 'Night Drive',
        artist: 'Tiger',
        genre: 'Electronic',
        duration: const Duration(seconds: 12),
      );
      await library.toggleFavorite(track.id);
      await library.recordUse(track.id);
      await source.delete();
      final reopened = MusicLibrary(library.root);
      await reopened.load();
      expect(reopened.search('tiger').single.title, 'Night Drive');
      expect(
        reopened.search('', genre: 'Electronic', favoritesOnly: true).length,
        1,
      );
      expect(await File(reopened.tracks.single.path).exists(), true);
      expect(reopened.history.single, track.id);
      expect(reopened.tracks.single.license.synchronizationAllowed, false);
    },
  );

  test(
    'ten deterministic original sounds have valid bounded PCM WAV headers',
    () async {
      final sounds = await SoundLibrary(Directory('${temp.path}/sounds'))
          .generate();
      expect(sounds.length, 10);
      for (final sound in sounds) {
        final bytes = await File(sound.path).readAsBytes();
        expect(ascii.decode(bytes.sublist(0, 4)), 'RIFF');
        expect(ascii.decode(bytes.sublist(8, 12)), 'WAVE');
        expect(
          bytes.length,
          44 + (sound.duration.inMicroseconds * 22050 ~/ 1000000) * 2,
        );
        expect(sound.duration.inMilliseconds, inInclusiveRange(80, 1600));
      }
      final first = await File(sounds.first.path).readAsBytes();
      await File(sounds.first.path).delete();
      await SoundLibrary(Directory('${temp.path}/sounds')).generate();
      expect(await File(sounds.first.path).readAsBytes(), first);
    },
  );

  test(
    'semantic versions follow prerelease precedence and ignore build metadata',
    () {
      expect(
        SemanticVersion.parse('v3.1.0') > SemanticVersion.parse('3.1.0-rc.2'),
        true,
      );
      expect(
        SemanticVersion.parse('3.1.0-rc.10') >
            SemanticVersion.parse('3.1.0-rc.2'),
        true,
      );
      expect(
        SemanticVersion.parse('3.0.0+9')
            .compareTo(SemanticVersion.parse('3.0.0+1')),
        0,
      );
      expect(() => SemanticVersion.parse('3.01.0'), throwsFormatException);
    },
  );

  test(
    'updates select stable compatible assets and cache for 24h without login',
    () async {
      final transport = FakeTransport();
      final service = UpdateService(
        owner: 'owner',
        repository: 'repo',
        cacheFile: File('${temp.path}/updates.json'),
        transport: transport,
      );
      transport.responses.add(
        UpdateResponse(
          200,
          Stream.value(
            utf8.encode(
              jsonEncode([
                release('v4.0.0-rc.1', prerelease: true),
                release('v3.1.0'),
              ]),
            ),
          ),
        ),
      );
      final result = await service.check(
        currentVersion: '3.0.0',
        platform: UpdatePlatform.windowsX64,
      );
      expect(result.status, UpdateStatus.available);
      expect(result.release!.version.toString(), '3.1.0');
      expect(result.asset!.name, 'TigerVideoEdit-3.1.0-windows-x64-setup.exe');
      expect(transport.calls, 1);
      expect(
        (await service.check(
          currentVersion: '3.0.0',
          platform: UpdatePlatform.windowsX64,
        )).fromCache,
        true,
      );
      expect(transport.calls, 1);
      transport.responses.add(UpdateResponse(429, const Stream.empty()));
      expect(
        (await service.check(
          currentVersion: '3.0.0',
          platform: UpdatePlatform.windowsX64,
          force: true,
        )).status,
        UpdateStatus.rateLimited,
      );
    },
  );

  test('verified staged downloads preserve old destination on corrupt/cancel and reject foreign URLs', () async {
    final bytes = utf8.encode('installer');
    final transport = FakeTransport();
    final service = UpdateService(
      owner: 'owner',
      repository: 'repo',
      cacheFile: File('${temp.path}/cache'),
      transport: transport,
    );
    final destination = await File('${temp.path}/installer.exe')
        .writeAsString('old');
    UpdateAsset asset(String digest) => UpdateAsset(
      name: 'setup.exe',
      url: Uri.parse(
        'https://github.com/owner/repo/releases/download/v3.1.0/setup.exe',
      ),
      size: bytes.length,
      sha256: digest,
    );
    transport.responses.add(UpdateResponse(200, Stream.value(bytes)));
    await expectLater(
      service.download(asset('0' * 64), destination),
      throwsA(isA<UpdateException>()),
    );
    expect(await destination.readAsString(), 'old');
    final cancellation = DownloadCancellation();
    transport.responses.add(
      UpdateResponse(
        200,
        (() async* {
          yield bytes.sublist(0, 2);
          cancellation.cancel();
          yield bytes.sublist(2);
        })(),
      ),
    );
    await expectLater(
      service.download(
        asset(sha256.convert(bytes).toString()),
        destination,
        cancellation: cancellation,
      ),
      throwsA(isA<UpdateException>()),
    );
    expect(await destination.readAsString(), 'old');
    transport.responses.add(UpdateResponse(200, Stream.value(bytes)));
    await service.download(
      asset(sha256.convert(bytes).toString()),
      destination,
    );
    expect(await destination.readAsBytes(), bytes);
    await expectLater(
      service.download(
        UpdateAsset(
          name: 'x.exe',
          url: Uri.parse('https://evil.example/setup.exe'),
          size: 1,
          sha256: '0' * 64,
        ),
        destination,
      ),
      throwsA(isA<UpdateException>()),
    );
    expect(
      (await temp.list().toList())
          .where((f) => f.path.contains('.part'))
          .isEmpty,
      true,
    );
  });
}

void extraServiceTests() {
  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('tve-extra-');
  });
  tearDown(() async {
    await temp.delete(recursive: true);
  });
  test('unconfigured updater never makes a request', () async {
    final transport = FakeTransport();
    final service = UpdateService(
      owner: '',
      repository: 'repo',
      cacheFile: File('${temp.path}/cache'),
      transport: transport,
    );
    expect(
      (await service.check(
        currentVersion: '3.0.0',
        platform: UpdatePlatform.androidArm64,
      )).status,
      UpdateStatus.notConfigured,
    );
    expect(transport.calls, 0);
  });
  test(
    'expired cache, timeout and offline errors retain last good cache',
    () async {
      var now = DateTime.utc(2026, 10, 31);
      final transport = FakeTransport();
      final service = UpdateService(
        owner: 'owner',
        repository: 'repo',
        cacheFile: File('${temp.path}/cache'),
        transport: transport,
        now: () => now,
      );
      transport.responses.add(
        UpdateResponse(
          200,
          Stream.value(utf8.encode(jsonEncode([release('v3.1.0')]))),
        ),
      );
      await service.check(
        currentVersion: '3.0.0',
        platform: UpdatePlatform.androidArm64,
      );
      final goodCache = await service.cacheFile.readAsString();
      now = now.add(const Duration(hours: 25));
      transport.failure = const SocketException('offline');
      expect(
        (await service.check(
          currentVersion: '3.0.0',
          platform: UpdatePlatform.androidArm64,
        )).status,
        UpdateStatus.offline,
      );
      expect(await service.cacheFile.readAsString(), goodCache);
      transport.failure = TimeoutException('timeout');
      expect(
        (await service.check(
          currentVersion: '3.0.0',
          platform: UpdatePlatform.androidArm64,
          force: true,
        )).status,
        UpdateStatus.timedOut,
      );
    },
  );
  test('failure backoff survives launches but manual retry and success cache take priority', () async {
    var clock = DateTime.utc(2026, 11, 1);
    final cache = File('${temp.path}/backoff-releases.json');
    final transport = FakeTransport();
    UpdateService launch({String repository = 'repo'}) => UpdateService(
      owner: 'owner',
      repository: repository,
      cacheFile: cache,
      transport: transport,
      now: () => clock,
    );
    Future<UpdateCheck> check(
      UpdateService service, {
      bool force = false,
      String version = '3.0.0',
      UpdatePlatform platform = UpdatePlatform.androidArm64,
    }) => service.check(
      currentVersion: version,
      platform: platform,
      force: force,
    );
    transport.responses.add(const UpdateResponse(429, Stream.empty()));
    final limited = await check(launch());
    expect(limited.status, UpdateStatus.rateLimited);
    final cached = await check(launch());
    expect(cached.status, limited.status);
    expect(cached.message, limited.message);
    expect(cached.fromCache, true);
    expect(transport.calls, 1);
    transport.failure = const SocketException('offline');
    expect((await check(launch(), force: true)).status, UpdateStatus.offline);
    expect((await check(launch())).status, UpdateStatus.offline);
    expect(transport.calls, 2);
    // A different installed version, platform or publisher must not reuse the failure.
    await check(launch(), version: '3.0.1');
    await check(launch(), platform: UpdatePlatform.windowsX64);
    await check(launch(repository: 'different'));
    expect(transport.calls, 5);
    clock = clock.add(const Duration(hours: 2));
    transport.failure = null;
    transport.responses.add(
      UpdateResponse(
        200,
        Stream.value(utf8.encode(jsonEncode([release('v3.1.0')]))),
      ),
    );
    expect((await check(launch())).status, UpdateStatus.available);
    final validCache = await cache.readAsString();
    expect(transport.calls, 6);
    transport.responses.add(const UpdateResponse(404, Stream.empty()));
    expect(
      (await check(launch(), force: true)).status,
      UpdateStatus.serverError,
    );
    expect(await cache.readAsString(), validCache);
    expect((await check(launch())).status, UpdateStatus.available);
    expect(transport.calls, 7);
    // Once the valid release cache expires, failure must not become an old update notice.
    clock = clock.add(const Duration(hours: 25));
    transport.failure = const SocketException('offline');
    expect((await check(launch())).status, UpdateStatus.offline);
    expect((await check(launch())).fromCache, true);
    expect(transport.calls, 8);
    transport.failure = null;
    // Manual successful retry clears the failure metadata even with an existing cache.
    transport.responses.add(
      UpdateResponse(200, Stream.value(utf8.encode('[]'))),
    );
    expect((await check(launch(), force: true)).status, UpdateStatus.upToDate);
    expect(await File('${cache.path}.attempt.json').exists(), false);
    expect((await check(launch())).status, UpdateStatus.upToDate);
    expect(transport.calls, 9);
  });
  test('external digest manifest matches exact installer name and rejects ambiguity', () async {
    final bytes = utf8.encode('verified installer');
    final transport = FakeTransport();
    final service = UpdateService(
      owner: 'owner',
      repository: 'repo',
      cacheFile: File('${temp.path}/cache'),
      transport: transport,
    );
    final destination = File('${temp.path}/installer.apk');
    final asset = UpdateAsset(
      name: 'app.apk',
      size: bytes.length,
      url: Uri.parse(
        'https://github.com/owner/repo/releases/download/v3.1.0/app.apk',
      ),
      checksumUrl: Uri.parse(
        'https://github.com/owner/repo/releases/download/v3.1.0/SHA256SUMS.txt',
      ),
    );
    final hash = sha256.convert(bytes).toString();
    transport.responses.add(
      UpdateResponse(
        200,
        Stream.value(utf8.encode('$hash  app.apk\n${'0' * 64}  other.apk')),
      ),
    );
    transport.responses.add(UpdateResponse(200, Stream.value(bytes)));
    await service.download(asset, destination);
    expect(await destination.readAsBytes(), bytes);
    transport.responses.add(
      UpdateResponse(
        200,
        Stream.value(utf8.encode('$hash  app.apk\n$hash  app.apk')),
      ),
    );
    await expectLater(
      service.download(asset, destination),
      throwsA(isA<UpdateException>()),
    );
    expect(await destination.readAsBytes(), bytes);
  });
  test(
    'online rights require download, offline and synchronization permissions',
    () {
      final track = OnlineMusicTrack(
        id: '1',
        title: 'A',
        artist: 'B',
        duration: Duration.zero,
        downloadUrl: Uri.parse('https://example.com/song.mp3'),
        license: const MusicLicense(downloadAllowed: true),
      );
      expect(track.canDownload, false);
      expect(MusicSources.jamendoUnavailableReason, contains('agreement'));
    },
  );
}

Map<String, Object?> release(String tag, {bool prerelease = false}) => {
  'tag_name': tag,
  'draft': false,
  'prerelease': prerelease,
  'body': 'Changes',
  'assets': [
    {
      'name': 'TigerVideoEdit-3.1.0-windows-x64-setup.exe',
      'size': 9,
      'digest': 'sha256:${'0' * 64}',
      'browser_download_url':
          'https://github.com/owner/repo/releases/download/$tag/TigerVideoEdit-3.1.0-windows-x64-setup.exe',
    },
    {
      'name': 'TigerVideoEdit-3.1.0-android-arm64.apk',
      'size': 9,
      'digest': 'sha256:${'0' * 64}',
      'browser_download_url':
          'https://github.com/owner/repo/releases/download/$tag/TigerVideoEdit-3.1.0-android-arm64.apk',
    },
  ],
};

class FakeTransport implements UpdateTransport {
  final responses = <UpdateResponse>[];
  Object? failure;
  int calls = 0;
  @override
  Future<UpdateResponse> get(
    Uri uri, {
    Map<String, String> headers = const {},
  }) async {
    calls++;
    expect(headers.containsKey('Authorization'), false);
    if (failure != null) throw failure!;
    return responses.removeAt(0);
  }
}
