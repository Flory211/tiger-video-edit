import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:tiger_video_edit/model.dart';
import 'package:tiger_video_edit/platform_media.dart';

Future<void> tone(String path) async {
  const rate = 44100, count = rate * 2;
  final b = ByteData(44 + count * 2);
  void tag(int at, String text) {
    for (var i = 0; i < text.length; i++) {
      b.setUint8(at + i, text.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  b.setUint32(4, b.lengthInBytes - 8, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  b.setUint32(16, 16, Endian.little);
  b.setUint16(20, 1, Endian.little);
  b.setUint16(22, 1, Endian.little);
  b.setUint32(24, rate, Endian.little);
  b.setUint32(28, rate * 2, Endian.little);
  b.setUint16(32, 2, Endian.little);
  b.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  b.setUint32(40, count * 2, Endian.little);
  for (var i = 0; i < count; i++) {
    b.setInt16(44 + i * 2, (i % 100 < 50 ? 4000 : -4000), Endian.little);
  }
  await File(path).writeAsBytes(b.buffer.asUint8List());
}

Future<void> png(String path, ui.Color color) async {
  final r = ui.PictureRecorder();
  final c = ui.Canvas(r);
  c.drawColor(color, ui.BlendMode.src);
  final pic = r.endRecording();
  final image = await pic.toImage(64, 64);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  await File(path).writeAsBytes(bytes!.buffer.asUint8List());
  image.dispose();
  pic.dispose();
}

void main() {
  test('cancelled render preserves an existing destination', () async {
    if (!Platform.isWindows) return;
    final dir = await Directory.systemTemp.createTemp('leos_cancel');
    try {
      await tone('${dir.path}/sound.wav');
      await png('${dir.path}/A.png', const ui.Color(0xffff0000));
      final p = Project(
        audio: '${dir.path}/sound.wav',
        durationUs: 2000000,
        endUs: 2000000,
        images: [Still(path: '${dir.path}/A.png')],
      );
      final out = File('${dir.path}/out.mp4');
      await out.writeAsString('keep existing');
      final job = VideoExporter();
      await expectLater(
        job.export(p, out.path, (progress) {
          if (progress > 0.11) job.cancel();
        }),
        throwsA(isA<ExportCancelled>()),
      );
      expect(await out.readAsString(), 'keep existing');
      expect(await File('${out.path}.tve-pending').exists(), isFalse);
    } finally {
      await dir.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
  TestWidgetsFlutterBinding.ensureInitialized();
  test('real MP4 contains H264 AAC and correct image boundary', () async {
    if (!Platform.isWindows) return;
    final dir = await Directory.systemTemp.createTemp('leos_тест_');
    try {
      await tone('${dir.path}/sound.wav');
      await png('${dir.path}/A.png', const ui.Color(0xffff0000));
      await png('${dir.path}/B.png', const ui.Color(0xff0000ff));
      final p = Project(
        audio: '${dir.path}/sound.wav',
        durationUs: 2000000,
        startUs: 200000,
        endUs: 1200000,
        images: [
          Still(path: '${dir.path}/A.png'),
          Still(path: '${dir.path}/B.png'),
        ],
        markers: [Marker(id: 'a', timeUs: 700001)],
      );
      final progress = <double>[];
      final out = '${dir.path}/результат.mp4';
      await VideoExporter().export(p, out, progress.add);
      expect(progress.last, 1);
      await validateVideo(out, 1);
      Future<List<int>> pixel(int frame) async {
        final result = await Process.run(mediaTool('ffmpeg'), [
          '-v',
          'error',
          '-i',
          out,
          '-vf',
          'select=eq(n\\,$frame),scale=1:1',
          '-frames:v',
          '1',
          '-f',
          'rawvideo',
          '-pix_fmt',
          'rgb24',
          'pipe:1',
        ], stdoutEncoding: null);
        expect(result.exitCode, 0, reason: result.stderr.toString());
        return result.stdout as List<int>;
      }

      final before = await pixel(15), after = await pixel(16);
      expect(before[0], greaterThan(before[2] + 100));
      expect(after[2], greaterThan(after[0] + 100));
      final bins = await waveform(p.audio!, p.durationUs);
      expect(bins.length, 2000);
      expect(bins.any((v) => v > 0), isTrue);
    } finally {
      await dir.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
  test('missing or corrupt images fail without creating output', () async {
    final dir = await Directory.systemTemp.createTemp('leos_bad_');
    try {
      await tone('${dir.path}/sound.wav');
      final p = Project(
        audio: '${dir.path}/sound.wav',
        durationUs: 2000000,
        endUs: 1000000,
        images: [Still(path: '${dir.path}/missing.png')],
      );
      await expectLater(
        VideoExporter().export(p, '${dir.path}/out.mp4', (_) {}),
        throwsA(isA<FileSystemException>()),
      );
      await File('${dir.path}/missing.png').writeAsString('not an image');
      await expectLater(
        VideoExporter().export(p, '${dir.path}/out.mp4', (_) {}),
        throwsA(anything),
      );
      expect(await File('${dir.path}/out.mp4').exists(), isFalse);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
