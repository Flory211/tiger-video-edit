import 'dart:io';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tiger_video_edit/jamendo.dart';
import 'package:tiger_video_edit/model.dart';

Map<String, dynamic> row({String license = 'by', bool download = true}) => {
  'id': '12',
  'name': 'Piano',
  'artist_name': 'Artist',
  'duration': 123,
  'audio': 'https://prod-1.storage.jamendo.com/audio.mp3',
  'audiodownload': 'https://prod-1.storage.jamendo.com/download.mp3',
  'audiodownload_allowed': download,
  'shareurl': 'https://www.jamendo.com/track/12',
  'license_ccurl': 'http://creativecommons.org/licenses/$license/4.0/',
  'musicinfo': {
    'tags': {
      'genres': ['piano'],
    },
  },
};

void main() {
  test('relay close handles an upstream cancellation failure', () async {
    late StreamController<List<int>> upstream;
    upstream = StreamController<List<int>>(
      onListen: () => upstream.add([1, 2, 3]),
      onCancel: () =>
          Future<void>.error(const JamendoException('Cancelled network read')),
    );
    final track = JamendoProvider.parseTrack(row())!;
    final preview = await JamendoPreview.start(track, (_) => upstream.stream);
    final client = HttpClient();
    try {
      final response = await (await client.getUrl(preview.uri)).close();
      final started = Completer<void>();
      final subscription = response.listen((_) {
        if (!started.isCompleted) started.complete();
      }, onError: (Object _) {});
      await started.future.timeout(const Duration(seconds: 2));
      await preview.close();
      await subscription.cancel();
    } finally {
      client.close(force: true);
      await preview.close();
      await upstream.close();
    }
  });
  test('preview relay is loopback-only, rejects wrong paths, and cancels upstream on close', () async {
    final cancelled = Completer<void>();
    late StreamController<List<int>> upstream;
    upstream = StreamController<List<int>>(
      onListen: () => upstream.add([1, 2, 3]),
      onCancel: () => cancelled.complete(),
    );
    final p = JamendoProvider(
      clientId: 'fixture-id',
      getJson: (_) async => {
        'headers': {'status': 'success'},
        'results': [row()],
      },
      audioStream: (_) => upstream.stream,
    );
    final preview = await p.openPreview(JamendoProvider.parseTrack(row())!);
    final client = HttpClient();
    try {
      expect(preview.uri.host, '127.0.0.1');
      expect(preview.uri.path.endsWith('.mp3'), true);
      final bad = await (await client.getUrl(
        preview.uri.replace(path: '/wrong.mp3'),
      )).close();
      expect(bad.statusCode, 403);
      await bad.drain<void>();
      final started = Completer<void>();
      final response = await (await client.getUrl(preview.uri)).close();
      final subscription = response.listen((bytes) {
        if (!started.isCompleted) started.complete();
      }, onError: (Object _) {});
      await started.future.timeout(const Duration(seconds: 2));
      await preview.close();
      await cancelled.future.timeout(const Duration(seconds: 2));
      await subscription.cancel();
    } finally {
      client.close(force: true);
      await preview.close();
      await upstream.close();
    }
  });

  test(
    'cancelling while fresh metadata is pending never opens audio',
    () async {
      final metadata = Completer<Map<String, dynamic>>();
      var audioCalls = 0, cancel = false;
      final dir = Directory.systemTemp.createTempSync(
        'tiger-jamendo-cancel-metadata-',
      );
      addTearDown(() => dir.deleteSync(recursive: true));
      final p = JamendoProvider(
        clientId: 'fixture-id',
        editingApproved: true,
        getJson: (_) => metadata.future,
        audioStream: (_) {
          audioCalls++;
          return Stream.value([1]);
        },
      );
      final future = p.prepareForEditing(
        JamendoProvider.parseTrack(row(), editingApproved: true)!,
        dir,
        cancelled: () => cancel,
      );
      final assertion = expectLater(future, throwsA(isA<JamendoException>()));
      cancel = true;
      metadata.complete({
        'headers': {'status': 'success'},
        'results': [row()],
      });
      await assertion;
      expect(audioCalls, 0);
      expect(dir.listSync(), isEmpty);
    },
  );
  test('editing refresh rejects withdrawn rights and cleans cancelled partial files', () async {
    final dir = Directory.systemTemp.createTempSync('tiger-jamendo-download-');
    addTearDown(() => dir.deleteSync(recursive: true));
    var audioCalls = 0;
    var allow = false;
    var cancelled = false;
    final provider = JamendoProvider(
      clientId: 'fixture-id',
      editingApproved: true,
      getJson: (_) async => {
        'headers': {'status': 'success'},
        'results': [row(download: allow)],
      },
      audioStream: (_) {
        audioCalls++;
        return Stream.fromIterable([
          [1, 2],
          [3, 4],
        ]);
      },
    );
    final track = JamendoProvider.parseTrack(row(), editingApproved: true)!;
    await expectLater(
      provider.prepareForEditing(track, dir),
      throwsA(isA<JamendoException>()),
    );
    expect(audioCalls, 0);
    allow = true;
    await expectLater(
      provider.prepareForEditing(
        track,
        dir,
        cancelled: () => cancelled,
        onProgress: (_) => cancelled = true,
      ),
      throwsA(isA<JamendoException>()),
    );
    expect(dir.listSync(), isEmpty);
    final (file, fresh) = await provider.prepareForEditing(track, dir);
    expect(await file.readAsBytes(), [1, 2, 3, 4]);
    expect(fresh.id, track.id);
  });
  test('music credit survives project JSON, copies and undo; old projects default empty', () {
    final p = Project(
      musicCredit:
          'Piano — Artist. CC BY 4.0; https://www.jamendo.com/track/12',
    );
    expect(
      Project.fromJson(p.toJson()).copy(name: 'Edit').musicCredit,
      p.musicCredit,
    );
    final history = ProjectHistory(p);
    history.change(p.copy(musicCredit: 'Other track'));
    history.undo();
    expect(history.current.musicCredit, p.musicCredit);
    final old = p.toJson()..remove('musicCredit');
    expect(Project.fromJson(old).musicCredit, isEmpty);
    expect(
      () => Project(musicCredit: 'x' * 8193).validate(),
      throwsFormatException,
    );
  });
  test('ND/NC/SA and artist download refusal never enable editing', () {
    for (final license in ['by-nd', 'by-nc', 'by-sa', 'by-nc-nd']) {
      expect(
        JamendoProvider.parseTrack(
          row(license: license),
          editingApproved: true,
        )!.canDownload,
        false,
      );
    }
    expect(
      JamendoProvider.parseTrack(
        row(download: false),
        editingApproved: true,
      )!.canDownload,
      false,
    );
    expect(JamendoProvider.parseTrack(row())!.canDownload, false);
    final permitted = JamendoProvider.parseTrack(row(), editingApproved: true)!;
    expect(permitted.canDownload, true);
    expect(permitted.license.attribution, contains('Artist'));
    expect(
      permitted.license.attribution,
      contains('https://www.jamendo.com/track/12'),
    );
  });

  test('unsafe hosts, fake CC domains and non-finite metadata rejected', () {
    expect(
      JamendoProvider.safeAudio(
        Uri.parse('https://jamendo.com.evil.test/a.mp3'),
      ),
      false,
    );
    expect(
      JamendoProvider.safeAudio(Uri.parse('https://127.0.0.1/a.mp3')),
      false,
    );
    expect(
      JamendoProvider.safeAudio(
        Uri.parse('https://u:p@prod-1.storage.jamendo.com/a'),
      ),
      false,
    );
    expect(
      JamendoProvider.safeAudio(
        Uri.parse('http://prod-1.storage.jamendo.com/a'),
      ),
      false,
    );
    expect(
      JamendoProvider.parseTrack({...row(), 'duration': double.infinity}),
      isNull,
    );
    expect(
      JamendoProvider.parseTrack({
        ...row(),
        'license_ccurl':
            'https://creativecommons.org.evil.test/licenses/by/4.0/',
      }, editingApproved: true)!.canDownload,
      false,
    );
  });

  test(
    'search is explicit, bounded, paged, cached and escapes user input',
    () async {
      final requests = <Map<String, String>>[];
      final p = JamendoProvider(
        clientId: 'fixture-id',
        getJson: (params) async {
          requests.add(params);
          return {
            'headers': {'status': 'success'},
            'results': [row()],
          };
        },
      );
      expect(requests, isEmpty);
      final result = await p.searchPage(
        'piano & drums',
        genre: 'electronic',
        page: 2,
      );
      expect(result.tracks.single.title, 'Piano');
      expect(requests.single['search'], 'piano & drums');
      expect(requests.single['offset'], '20');
      expect(requests.single['type'], 'single albumtrack');
      expect(requests.single['tags'], 'electronic');
      await p.searchPage('piano & drums', genre: 'electronic', page: 2);
      expect(requests.length, 1);
      await expectLater(p.searchPage('x', page: 0), throwsArgumentError);
      await expectLater(
        JamendoProvider(clientId: '').searchPage('x'),
        throwsA(isA<JamendoException>()),
      );
    },
  );

  test(
    'API failures do not leak credentials or cache a failed search',
    () async {
      var calls = 0;
      final p = JamendoProvider(
        clientId: 'private-fixture',
        getJson: (_) async {
          calls++;
          return {
            'headers': {
              'status': 'failed',
              'code': 4,
              'error_message': 'private-fixture',
            },
            'results': [],
          };
        },
      );
      for (var i = 0; i < 2; i++) {
        try {
          await p.searchPage('x');
          fail('must fail');
        } on JamendoException catch (e) {
          expect('$e', isNot(contains('private-fixture')));
        }
      }
      expect(calls, 2);
    },
  );

  test(
    'unapproved editing refuses before network or filesystem writes',
    () async {
      final dir = Directory.systemTemp.createTempSync('tiger-jamendo-gate-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final p = JamendoProvider(
        clientId: 'fixture-id',
        getJson: (_) async => throw StateError('no request expected'),
      );
      await expectLater(
        p.prepareForEditing(JamendoProvider.parseTrack(row())!, dir),
        throwsA(isA<JamendoException>()),
      );
      expect(dir.listSync(), isEmpty);
    },
  );
}
