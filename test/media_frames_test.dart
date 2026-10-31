import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:tiger_video_edit/media_frames.dart';
import 'package:tiger_video_edit/model.dart';
import 'package:tiger_video_edit/media_bridge.dart';

Future<int> red(ui.Image image) async {
  final bytes = await image.toByteData();
  return bytes!.getUint8(0);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    '25fps seek anchors match sequential, direct and backward frames',
    () async {
      if (!Platform.isWindows) return;
      final dir = await Directory.systemTemp.createTemp('tiger_anchors_');
      final sequential = MediaFrameSource(maxDimension: 64);
      final seek = MediaFrameSource(maxDimension: 64);
      try {
        final path = '${dir.path}/moving.mp4';
        final result = await Process.run(mediaTool('ffmpeg'), [
          '-v',
          'error',
          '-f',
          'lavfi',
          '-i',
          'testsrc2=s=64x32:r=25:d=2.12',
          '-y',
          path,
        ]);
        expect(result.exitCode, 0, reason: '${result.stderr}');
        final info = await inspectMedia(path);
        final item = Still(path: path, durationUs: info.durationUs);
        final reference = <int, List<int>>{};
        for (var index = 0; index < 64; index++) {
          final time = (index * 1000000 + 29) ~/ 30;
          final image = await sequential.frame(item, time);
          if ([0, 29, 30, 31, 59, 60, 61, 63].contains(index)) {
            reference[index] = (await image.toByteData())!.buffer
                .asUint8List()
                .toList();
          }
          image.dispose();
        }
        for (final index in [31, 30, 61, 59, 60, 29, 63, 0]) {
          final time = (index * 1000000 + 29) ~/ 30;
          final image = await seek.frame(item, time);
          expect(
            (await image.toByteData())!.buffer.asUint8List(),
            orderedEquals(reference[index]!),
            reason: 'frame=$index',
          );
          image.dispose();
        }
        final loop = await seek.frame(item, info.durationUs);
        expect(
          (await loop.toByteData())!.buffer.asUint8List(),
          orderedEquals(reference[0]!),
        );
        loop.dispose();
      } finally {
        await sequential.dispose();
        await seek.dispose();
        await dir.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
  test('missing media reports an error', () async {
    final source = MediaFrameSource();
    await expectLater(inspectMedia('does-not-exist.png'), throwsA(anything));
    await expectLater(
      source.frame(const Still(path: 'does-not-exist.png'), 0),
      throwsA(anything),
    );
    await source.dispose();
  });
  test('rotated video uses display dimensions when decoding', () async {
    if (!Platform.isWindows) return;
    final dir = await Directory.systemTemp.createTemp('tiger_rotation_');
    final source = MediaFrameSource(maxDimension: 32);
    try {
      final base = '${dir.path}/base.mp4';
      final path = '${dir.path}/rotated.mp4';
      var result = await Process.run(mediaTool('ffmpeg'), [
        '-v',
        'error',
        '-f',
        'lavfi',
        '-i',
        'color=red:s=64x32:r=30:d=0.2',
        '-y',
        base,
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      result = await Process.run(mediaTool('ffmpeg'), [
        '-v',
        'error',
        '-display_rotation:v:0',
        '90',
        '-i',
        base,
        '-c',
        'copy',
        '-y',
        path,
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      final info = await inspectMedia(path);
      expect(info.width, 32);
      expect(info.height, 64);
      final image = await source.frame(Still(path: path), 0);
      expect(image.width, 16);
      expect(image.height, 32);
      expect(await red(image), greaterThan(200));
      image.dispose();
    } finally {
      await source.dispose();
      await dir.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
  test(
    'short 25fps video retains the final frame through its valid tail',
    () async {
      if (!Platform.isWindows) return;
      final dir = await Directory.systemTemp.createTemp('tiger_tail_');
      final source = MediaFrameSource(maxDimension: 32);
      try {
        final path = '${dir.path}/short.mp4';
        final result = await Process.run(mediaTool('ffmpeg'), [
          '-v',
          'error',
          '-f',
          'lavfi',
          '-i',
          'color=red:s=32x32:r=25:d=0.08',
          '-y',
          path,
        ]);
        expect(result.exitCode, 0, reason: '${result.stderr}');
        final info = await inspectMedia(path);
        expect(info.durationUs, 80000);
        final item = Still(path: path, durationUs: info.durationUs);
        for (final time in [0, 33334, 66667, 79999, 80000, 146667, 159999]) {
          final image = await source.frame(item, time);
          expect(await red(image), greaterThan(200), reason: 'time=$time');
          image.dispose();
        }
        final malformed = File('${dir.path}/broken.mp4');
        await malformed.writeAsString('not a video');
        await expectLater(
          source.frame(Still(path: malformed.path), 0),
          throwsA(isA<FormatException>()),
        );
      } finally {
        await source.dispose();
        await dir.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
  test('real images, GIF and video seek, loop and caller ownership', () async {
    if (!Platform.isWindows) return;
    final dir = await Directory.systemTemp.createTemp('tiger_frames_');
    final source = MediaFrameSource(maxDimension: 32);
    try {
      for (final ext in ['gif', 'mp4', 'png']) {
        final path = '${dir.path}/sample.$ext';
        final result = await Process.run(mediaTool('ffmpeg'), [
          '-v',
          'error',
          '-f',
          'lavfi',
          '-i',
          'color=red:s=64x32:r=10:d=0.5',
          '-f',
          'lavfi',
          '-i',
          'color=blue:s=64x32:r=10:d=0.5',
          '-filter_complex',
          '[0:v][1:v]concat=n=2:v=1:a=0[v]',
          '-map',
          '[v]',
          if (ext == 'png') ...['-frames:v', '1'],
          '-y',
          path,
        ]);
        expect(result.exitCode, 0, reason: '${result.stderr}');
        final info = await inspectMedia(path);
        expect(info.width, 64);
        expect(info.height, 32);
        if (ext != 'png') expect(info.durationUs, closeTo(1000000, 100000));
        final item = Still(path: path, durationUs: info.durationUs);
        final first = await source.frame(item, 0);
        expect(first.width, 32);
        expect(await red(first), greaterThan(200));
        if (ext != 'png') {
          final later = await source.frame(item, 700000);
          expect(await red(later), lessThan(50));
          later.dispose();
          final loop = await source.frame(item, info.durationUs + 100000);
          expect(await red(loop), greaterThan(200));
          loop.dispose();
          final offset = await source.frame(
            item.copy(sourceStartUs: 600000),
            0,
          );
          expect(await red(offset), lessThan(50));
          offset.dispose();
          final last = await source.frame(item, info.durationUs - 1);
          expect(await red(last), lessThan(50));
          last.dispose();
          final backward = await source.frame(item, 0);
          expect(await red(backward), greaterThan(200));
          backward.dispose();
        }
        // Advancing, restarting and disposing must never invalidate caller images.
        expect(await red(first), greaterThan(200));
        first.dispose();
      }
      final retained = await source.frame(
        Still(path: '${dir.path}/sample.png'),
        0,
      );
      await source.dispose();
      expect(await red(retained), greaterThan(200));
      retained.dispose();
      await expectLater(
        source.frame(Still(path: '${dir.path}/sample.png'), 0),
        throwsStateError,
      );
    } finally {
      await source.dispose();
      await dir.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
