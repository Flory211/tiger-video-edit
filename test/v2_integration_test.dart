import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiger_video_edit/main.dart';
import 'package:tiger_video_edit/model.dart';
import 'package:tiger_video_edit/platform_media.dart';
import 'package:tiger_video_edit/storage.dart';
import 'package:tiger_video_edit/editor.dart';
import 'package:tiger_video_edit/beat.dart';

import 'editor_test.dart' show DeviceAudio;
import 'export_test.dart' show tone;

void main() {
  test('custom preset persists and beat assembly is one undo step', () async {
    final dir = await Directory.systemTemp.createTemp('tiger_v2_settings');
    final e = Editor(LocalLibrary(dir), DeviceAudio());
    Editor? reopened;
    try {
      e.change(
        Project(
          audio: 'track.wav',
          durationUs: 3000000,
          startUs: 500000,
          endUs: 2500000,
          images: [
            Still(path: 'a', effects: {'zoom': .6}, effectDurationUs: 800000),
            Still(path: 'b'),
          ],
        ),
      );
      await e.savePreset('Мой пресет');
      reopened = Editor(LocalLibrary(dir), DeviceAudio());
      await reopened.initialize();
      expect(reopened.presets['Мой пресет']!.effects['zoom'], .6);
      e.applyPreset('Мой пресет', all: true);
      expect(e.project.images.last.effects['zoom'], .6);
      e.beatAnalysis = BeatAnalysis(
        timesUs: [0, 500000, 1000000, 1000000, 2000000, 2500000],
      );
      e.applyBeats();
      expect(e.project.markers.map((m) => m.timeUs), [1000000, 2000000]);
      await e.undo();
      expect(e.project.markers, isEmpty);
    } finally {
      e.dispose();
      reopened?.dispose();
      await dir.delete(recursive: true);
    }
  });
  TestWidgetsFlutterBinding.ensureInitialized();
  test('changing audio by undo clears previously analyzed beats', () async {
    final dir = await Directory.systemTemp.createTemp('tiger_beat_history');
    final e = Editor(LocalLibrary(dir), DeviceAudio());
    try {
      e.change(Project(audio: 'A.wav', durationUs: 10000000, endUs: 10000000));
      e.change(e.project.copy(audio: 'B.wav'));
      e.beatAnalysis = BeatAnalysis(timesUs: [1000000, 2000000]);
      await e.undo();
      expect(e.beatAnalysis, isNull);
    } finally {
      e.dispose();
      await dir.delete(recursive: true);
    }
  });
  testWidgets('paused GIF preview reloads when clip offset changes', (
    tester,
  ) async {
    if (!Platform.isWindows) return;
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('tiger_offset'),
    ))!;
    final path = '${dir.path}/two.gif';
    await tester.runAsync(() async {
      final result = await Process.run(mediaTool('ffmpeg'), [
        '-v',
        'error',
        '-f',
        'lavfi',
        '-i',
        'color=red:s=32x32:r=5:d=0.2',
        '-f',
        'lavfi',
        '-i',
        'color=blue:s=32x32:r=5:d=0.2',
        '-filter_complex',
        '[0:v][1:v]concat=n=2:v=1:a=0',
        '-y',
        path,
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
    });
    Future<int> mountAt(int offset) async {
      final item = Still(path: path, durationUs: 400000, sourceStartUs: offset);
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 64,
            height: 64,
            child: StillView(
              key: const ValueKey('preview'),
              still: item,
              project: Project(images: [item]),
            ),
          ),
        ),
      );
      for (var attempt = 0; attempt < 100; attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
        if (tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .any((w) => w.painter is StillPainter)) {
          break;
        }
      }
      final paints = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .where((w) => w.painter is StillPainter);
      expect(paints, isNotEmpty);
      final image = (paints.first.painter! as StillPainter).image;
      return (await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
      ))!.getUint8(0);
    }

    final red = await mountAt(0), blue = await mountAt(200000);
    expect(red, greaterThan(200));
    expect(blue, lessThan(30));
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => dir.delete(recursive: true));
  });
  test('real v2 MP4 renders video GIF captions and effects', () async {
    if (!Platform.isWindows) return;
    final dir = await Directory.systemTemp.createTemp('tiger_v2_export');
    try {
      await tone('${dir.path}/tone.wav');
      for (final ext in ['mp4', 'gif']) {
        final result = await Process.run(mediaTool('ffmpeg'), [
          '-v',
          'error',
          '-f',
          'lavfi',
          '-i',
          'color=red:s=64x64:r=30:d=0.5',
          '-f',
          'lavfi',
          '-i',
          'color=blue:s=64x64:r=30:d=0.5',
          '-filter_complex',
          '[0:v][1:v]concat=n=2:v=1:a=0',
          '-y',
          '${dir.path}/clip.$ext',
        ]);
        expect(result.exitCode, 0, reason: '${result.stderr}');
      }
      final p = Project(
        audio: '${dir.path}/tone.wav',
        durationUs: 2000000,
        startUs: 250000,
        endUs: 1250000,
        images: [
          Still(
            path: '${dir.path}/clip.mp4',
            durationUs: 1000000,
            effects: {'flash': .2, 'zoom': .25},
          ),
          Still(
            path: '${dir.path}/clip.gif',
            durationUs: 1000000,
            sourceStartUs: 500000,
            effects: {'glow': .2},
          ),
        ],
        markers: [Marker(id: 'a', timeUs: 750000)],
        captions: [
          Caption(
            id: 'a',
            text: 'TIGER 2',
            startUs: 250000,
            endUs: 750000,
            y: .5,
            fontSize: 120,
          ),
        ],
      );
      final path = '${dir.path}/result.mp4';
      await VideoExporter().export(p, path, (_) {});
      await validateVideo(path, 1);
      final result = await Process.run(mediaTool('ffmpeg'), [
        '-v',
        'error',
        '-i',
        path,
        '-vf',
        'select=eq(n\\,0)',
        '-frames:v',
        '1',
        '-f',
        'rawvideo',
        '-pix_fmt',
        'rgb24',
        'pipe:1',
      ], stdoutEncoding: null);
      expect(result.exitCode, 0);
      final bytes = result.stdout as List<int>;
      var white = 0;
      for (var i = 0; i + 2 < bytes.length; i += 3) {
        if (bytes[i] > 225 && bytes[i + 1] > 225 && bytes[i + 2] > 225) white++;
      }
      expect(
        white,
        greaterThan(1000),
        reason: 'Caption must be present on first output frame',
      );
    } finally {
      await dir.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
