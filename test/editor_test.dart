import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:tiger_video_edit/editor.dart';
import 'package:tiger_video_edit/main.dart';
import 'package:tiger_video_edit/model.dart';
import 'package:tiger_video_edit/platform_media.dart';
import 'package:tiger_video_edit/storage.dart';

class FakeStreams extends Fake implements PlayerStream {
  @override
  Stream<String> get error => const Stream.empty();
}

class DevicePlayer extends Fake implements Player {
  int time = 0;
  @override
  PlayerStream get stream => FakeStreams();
  @override
  Future<void> pause() async {}
  @override
  Future<void> play() async {}
  @override
  Future<void> seek(Duration value) async {
    time = value.inMicroseconds;
  }

  @override
  Future<void> dispose() async {}
}

class DeviceAudio extends Fake implements AudioEngine {
  @override
  final DevicePlayer player = DevicePlayer();
  final opened = <String>[];
  @override
  Future<int> open(String path) async {
    opened.add(path);
    return 10000000;
  }

  @override
  Future<int> positionUs() async => player.time;
}

void main() {
  test('saving legacy project creates tve and preserves original', () async {
    final dir = await Directory.systemTemp.createTemp('tiger_legacy_save');
    final e = Editor(LocalLibrary(dir), DeviceAudio());
    try {
      final old = '${dir.path}/project.leos';
      await ProjectStore.save(old, Project(name: 'Original'));
      e.projectPath = old;
      e.change(Project(name: 'Updated'));
      await e.save();
      expect(e.projectPath, endsWith('.tve'));
      expect((await ProjectStore.read(e.projectPath!)).name, 'Updated');
      expect((await ProjectStore.read(old)).name, 'Original');
    } finally {
      e.dispose();
      await dir.delete(recursive: true);
    }
  });
  test(
    'playback opens the source from current project after source changes',
    () async {
      final dir = await Directory.systemTemp.createTemp('leos_source');
      final audio = DeviceAudio();
      final e = Editor(LocalLibrary(dir), audio)..countdown = false;
      try {
        e.change(
          Project(audio: 'A.wav', durationUs: 10000000, endUs: 10000000),
        );
        await e.toggle();
        await e.stop();
        e.change(e.project.copy(audio: 'B.wav'));
        await e.toggle();
        expect(audio.opened, ['A.wav', 'B.wav']);
      } finally {
        e.dispose();
        await dir.delete(recursive: true);
      }
    },
  );
  test('first autosave registers an existing primary file', () async {
    final dir = await Directory.systemTemp.createTemp('leos_autosave');
    final e = Editor(LocalLibrary(dir), DeviceAudio());
    try {
      e.change(Project(name: 'recovery'));
      await e.save(autosave: true);
      expect(await File(e.recent.first).exists(), isTrue);
      expect((await ProjectStore.read(e.recent.first)).name, 'recovery');
      expect(await File('${e.projectPath}.autosave').exists(), isTrue);
    } finally {
      e.dispose();
      await dir.delete(recursive: true);
    }
  });
  test(
    'switching project waits for in-flight save and clears old destination',
    () async {
      final dir = await Directory.systemTemp.createTemp('leos_save_race');
      final e = Editor(BlockingLibrary(dir), DeviceAudio());
      final blocking = e.library as BlockingLibrary;
      try {
        e.change(Project(name: 'old'));
        final saving = e.save(autosave: true);
        await blocking.started.future;
        var switched = false;
        final switching = e.newProject('new').then((_) {
          switched = true;
        });
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(switched, isFalse);
        blocking.release.complete();
        await saving;
        await switching;
        expect(e.project.name, 'new');
        expect(e.projectPath, isNull);
      } finally {
        if (!blocking.release.isCompleted) blocking.release.complete();
        e.dispose();
        await dir.delete(recursive: true);
      }
    },
  );
  test('history clamps image selection and reloads changed audio', () async {
    final dir = await Directory.systemTemp.createTemp('leos_undo');
    final audio = DeviceAudio();
    final e = Editor(LocalLibrary(dir), audio);
    try {
      e.change(
        Project(
          audio: 'A.wav',
          durationUs: 10000000,
          endUs: 10000000,
          images: [Still(path: 'A')],
        ),
      );
      e.change(
        e.project.copy(
          audio: 'B.wav',
          images: [
            Still(path: 'A'),
            Still(path: 'B'),
          ],
        ),
      );
      e.selectedImage = 1;
      await e.undo();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(e.selectedImage, 0);
      expect(audio.opened.last, 'A.wav');
    } finally {
      e.dispose();
      await dir.delete(recursive: true);
    }
  });
  test(
    'marker uses device time after pause and seek; edits undo and redo',
    () async {
      final audio = DeviceAudio(),
          dir = await Directory.systemTemp.createTemp('leos_editor');
      final e = Editor(LocalLibrary(dir), audio)..countdown = false;
      try {
        e.change(
          Project(audio: 'sound.wav', durationUs: 10000000, endUs: 10000000),
        );
        audio.player.time = 1234567;
        e.playing = true;
        await e.capture();
        await e.stop();
        audio.player.time = 5555555;
        await e.capture();
        expect(e.project.markers.map((m) => m.timeUs), [1234567]);
        await e.seek(2345678);
        await e.toggle();
        await e.capture();
        expect(e.project.markers.map((m) => m.timeUs), [1234567, 2345678]);
        final id = e.project.markers.last.id;
        e.moveMarker(id, 2456789);
        expect(e.project.markers.last.timeUs, 2456789);
        await e.undo();
        expect(e.project.markers.last.timeUs, 2345678);
        await e.redo();
        expect(e.project.markers.last.timeUs, 2456789);
        e.selectedMarker = id;
        e.deleteMarker();
        expect(e.project.markers.length, 1);
      } finally {
        e.dispose();
        await dir.delete(recursive: true);
      }
    },
  );
  testWidgets('desktop and phone layout are usable without overflow', (
    tester,
  ) async {
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('leos_ui'),
    ))!;
    final e = Editor(LocalLibrary(dir), DeviceAudio());
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(TigerApp(editor: e));
    await tester.pump();
    expect(find.text('МЕДИАБИБЛИОТЕКА'), findsOneWidget);
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(390, 844);
    await tester.pump();
    expect(find.text('Медиа'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    await tester.runAsync(() => dir.delete(recursive: true));
  });
  testWidgets('G in a text field does not record a marker', (tester) async {
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('leos_key'),
    ))!;
    final audio = DeviceAudio();
    final e = Editor(LocalLibrary(dir), audio);
    e.change(Project(audio: 'x', durationUs: 10000000, endUs: 10000000));
    await tester.pumpWidget(TigerApp(editor: e));
    await tester.pump();
    await tester.tap(find.byTooltip('Настройки'));
    await tester.pumpAndSettle();
    final field = find.byType(TextFormField).first;
    await tester.tap(field);
    e.playing = true;
    audio.player.time = 1234567;
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.pump();
    expect(e.project.markers, isEmpty);
    e.playing = false;
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => dir.delete(recursive: true));
  });
}

class BlockingLibrary extends LocalLibrary {
  final started = Completer<void>(), release = Completer<void>();
  BlockingLibrary(super.root);
  @override
  Future<void> preferences(Map<String, dynamic> data) async {
    if (!started.isCompleted) started.complete();
    await release.future;
    await super.preferences(data);
  }
}
