import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tiger_video_edit/compositor.dart' as compositor;
import 'package:tiger_video_edit/model.dart';
import 'package:tiger_video_edit/platform_media.dart';
import 'package:tiger_video_edit/sound_library.dart';
import 'package:tiger_video_edit/storage.dart';

Future<ProcessResult> command(
  String tool,
  List<String> args, {
  bool binary = false,
}) async {
  final result = await Process.run(
    mediaTool(tool),
    args,
    stdoutEncoding: binary ? null : utf8,
  );
  if (result.exitCode != 0) {
    throw StateError('$tool failed (${result.exitCode}): ${result.stderr}');
  }
  return result;
}

Future<String> solid(Directory dir, String name, ui.Color color) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(color, ui.BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(854, 480);
  try {
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = await File('${dir.path}/$name.png')
        .writeAsBytes(png!.buffer.asUint8List());
    return file.path;
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Future<ui.Image> previewFrame(Project project, int frame) async {
  final sourceUs = project.startUs + frame * 1000000 ~/ project.frameRate;
  final segment = project.segmentAt(sourceUs)!;
  final segmentIndex = project.segments.indexWhere(
    (s) => s.startFrame == segment.startFrame,
  );
  final item = project.images[segment.imageIndex];
  final image = await decodeStill(item.path);
  final previousItem = segmentIndex > 0
      ? project.images[project.segments[segmentIndex - 1].imageIndex]
      : null;
  final previous = previousItem == null
      ? null
      : await decodeStill(previousItem.path);
  final overlays = <compositor.VisualFrame>[];
  final active = project.visualClips.where((c) => c.activeAt(sourceUs)).toList()
    ..sort((a, b) => a.track.compareTo(b.track));
  final recorder = ui.PictureRecorder();
  ui.Picture? picture;
  try {
    for (final clip in active) {
      overlays.add(
        compositor.VisualFrame(
          clip.media,
          await decodeStill(clip.media.path),
          sourceUs - clip.startUs,
          clip.opacity,
        ),
      );
    }
    compositor.paintFrame(
      ui.Canvas(recorder),
      ui.Size(project.width.toDouble(), project.height.toDouble()),
      image,
      item,
      project: project,
      sourceUs: sourceUs,
      localUs:
          ((frame - segment.startFrame) * 1000000 + project.frameRate - 1) ~/
          project.frameRate,
      captions: project.captions,
      referenceWidth: project.width.toDouble(),
      previousImage: previous,
      previousItem: previousItem,
      overlays: overlays,
    );
    picture = recorder.endRecording();
    return await picture.toImage(project.width, project.height);
  } finally {
    image.dispose();
    previous?.dispose();
    picture?.dispose();
    for (final overlay in overlays) {
      overlay.image.dispose();
    }
  }
}

Future<void> savePng(ui.Image image, String path) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  await File(path).writeAsBytes(data!.buffer.asUint8List());
}

List<int> pixel(ByteData rgba, int width, int x, int y) => [
  for (var c = 0; c < 3; c++) rgba.getUint8((y * width + x) * 4 + c),
];

double rms(ByteData samples, double from, double to) {
  final first = (from * 48000).round(),
      end = math.min((to * 48000).round(), samples.lengthInBytes ~/ 4);
  var sum = 0.0;
  for (var i = first; i < end; i++) {
    final v = samples.getFloat32(i * 4, Endian.little);
    sum += v * v;
  }
  return math.sqrt(sum / math.max(1, end - first));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('v3 real native export, preview parity, audio and cancellation', (
    tester,
  ) async {
    const root = String.fromEnvironment(
      'TVE_ROOT',
      defaultValue: 'C:/LeosFastVideoEditor',
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Text('Нативные шрифты Tiger 3.0')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final temp = await Directory.systemTemp.createTemp(
        'tve_v3_export_check_',
      );
      final ownPath = temp.absolute.path;
      try {
        final red = await solid(temp, 'red', const ui.Color(0xff6a2020));
        final blue = await solid(temp, 'blue', const ui.Color(0xff183c80));
        final green = await solid(temp, 'overlay', const ui.Color(0xff20b060));
        final sounds = await SoundLibrary(Directory('${temp.path}/sounds'))
            .generate();
        final pop = sounds.singleWhere((s) => s.id == 'pop');
        final project = Project(
          name: 'Native v3 acceptance',
          audio: '$root/demo/pulse.wav',
          durationUs: 10000000,
          startUs: 1000000,
          endUs: 2500000,
          frameRate: 24,
          resolution: 480,
          videoCrf: 18,
          images: [
            Still(path: red),
            Still(
              path: blue,
              effectStack: const [
                EffectInstance(
                  id: 'transition',
                  type: 'crossfade',
                  strength: 1,
                  durationUs: 500000,
                ),
              ],
            ),
          ],
          markers: const [Marker(id: 'cut', timeUs: 1500000)],
          globalEffects: const [
            GlobalAdjustmentLayer(
              id: 'global',
              effects: [
                EffectInstance(
                  id: 'flash',
                  type: 'flash',
                  strength: .15,
                  beginIntensity: 1,
                  endIntensity: 1,
                  durationUs: 100000,
                ),
              ],
            ),
          ],
          visualClips: [
            VisualClip(
              id: 'overlay',
              media: Still(path: green, scale: .3, x: .2, y: -.12),
              startUs: 1250000,
              durationUs: 1000000,
              opacity: .85,
            ),
          ],
          captions: const [
            Caption(
              id: 'title',
              text: 'ТЕСТ 3.0',
              startUs: 1000000,
              endUs: 2500000,
              fontSize: 48,
              y: .8,
            ),
          ],
          musicVolume: .25,
          soundVolume: .8,
          audioClips: [
            AudioClip(
              id: 'pop',
              path: pop.path,
              startUs: 1700000,
              durationUs: pop.duration.inMicroseconds,
              volume: 1.5,
              fadeInUs: 20000,
              fadeOutUs: 50000,
            ),
          ],
        );
        project.validate();
        expect(project.totalFrames, 36);
        final output = '${temp.path}/result.mp4';
        await VideoExporter().export(project, output, (_) {});
        final probe = jsonDecode(
          (await command('ffprobe', [
                '-v',
                'error',
                '-count_frames',
                '-show_streams',
                '-show_format',
                '-of',
                'json',
                output,
              ])).stdout
              as String,
        ) as Map<String, dynamic>;
        final streams = (probe['streams'] as List).cast<Map<String, dynamic>>();
        final video = streams.singleWhere((s) => s['codec_type'] == 'video');
        expect(video['codec_name'], 'h264');
        expect(
          streams.singleWhere((s) => s['codec_type'] == 'audio')['codec_name'],
          'aac',
        );
        expect(video['width'], 854);
        expect(video['height'], 480);
        expect(video['r_frame_rate'], '24/1');
        expect(int.parse(video['nb_read_frames'] as String), 36);
        expect(
          double.parse((probe['format'] as Map)['duration'] as String),
          closeTo(1.5, .08),
        );

        const frame = 18;
        final decodedPath = '${temp.path}/decoded.png';
        await command('ffmpeg', [
          '-v',
          'error',
          '-y',
          '-i',
          output,
          '-vf',
          'select=eq(n\\,18)',
          '-frames:v',
          '1',
          decodedPath,
        ]);
        final expected = await previewFrame(project, frame);
        final actual = await decodeStill(decodedPath);
        final noFlash = await previewFrame(
          project.copy(globalEffectsEnabled: false),
          frame,
        );
        try {
          final raw = (await actual.toByteData())!;
          final preview = (await expected.toByteData())!;
          final baseline = (await noFlash.toByteData())!;
          var error = 0.0;
          for (var offset = 0; offset < raw.lengthInBytes; offset += 4) {
            for (var c = 0; c < 3; c++) {
              error += (raw.getUint8(offset + c) - preview.getUint8(offset + c))
                  .abs();
            }
          }
          final mae = error / (actual.width * actual.height * 3);
          expect(
            mae,
            lessThan(6),
            reason: 'Canvas preview versus decoded H.264 RGB error',
          );
          final corner = pixel(raw, project.width, 30, 30);
          final unlit = pixel(baseline, project.width, 30, 30);
          expect(
            corner[0] - unlit[0],
            greaterThan(12),
            reason: 'held global flash must remain visible',
          );
          expect(corner[2] - unlit[2], greaterThan(12));
          final overlay = pixel(
            raw,
            project.width,
            (project.width * .7).round(),
            (project.height * .38).round(),
          );
          expect(overlay[1], greaterThan(overlay[0] + 25));
          expect(overlay[1], greaterThan(overlay[2] + 25));
          var white = 0,
              minX = project.width,
              maxX = 0,
              minY = project.height,
              maxY = 0;
          for (var y = 345; y < 425; y++) {
            for (var x = 220; x < 635; x++) {
              final p = pixel(raw, project.width, x, y);
              if (p.every((v) => v > 230)) {
                white++;
                minX = math.min(minX, x);
                maxX = math.max(maxX, x);
                minY = math.min(minY, y);
                maxY = math.max(maxY, y);
              }
            }
          }
          expect(
            white,
            greaterThan(500),
            reason: 'caption has visible glyph pixels',
          );
          final glyphCoverage = white / ((maxX - minX + 1) * (maxY - minY + 1));
          expect(
            glyphCoverage,
            inExclusiveRange(.1, .65),
            reason: 'native glyphs, not Ahem rectangular blocks',
          );
          await savePng(expected, '$root/docs/V3_NATIVE_PREVIEW.png');
          await savePng(actual, '$root/docs/V3_NATIVE_EXPORT_FRAME.png');
          debugPrint(
            'V3_FRAME_CHECK mae=$mae captionWhite=$white glyphCoverage=$glyphCoverage corner=$corner overlay=$overlay',
          );
        } finally {
          expected.dispose();
          actual.dispose();
          noFlash.dispose();
        }

        final decodedAudio = await command('ffmpeg', [
          '-v',
          'error',
          '-i',
          output,
          '-vn',
          '-ac',
          '1',
          '-ar',
          '48000',
          '-f',
          'f32le',
          'pipe:1',
        ], binary: true);
        final mainAudio = await command('ffmpeg', [
          '-v',
          'error',
          '-ss',
          '1',
          '-i',
          project.audio!,
          '-t',
          '1.5',
          '-vn',
          '-ac',
          '1',
          '-ar',
          '48000',
          '-f',
          'f32le',
          'pipe:1',
        ], binary: true);
        final audio = ByteData.sublistView(
          Uint8List.fromList(decodedAudio.stdout as List<int>),
        );
        final main = ByteData.sublistView(
          Uint8List.fromList(mainAudio.stdout as List<int>),
        );
        final difference = ByteData(
          math.min(audio.lengthInBytes, main.lengthInBytes),
        );
        for (var i = 0; i < difference.lengthInBytes; i += 4) {
          difference.setFloat32(
            i,
            audio.getFloat32(i, Endian.little) -
                main.getFloat32(i, Endian.little) * .25,
            Endian.little,
          );
        }
        expect(rms(audio, 0, 1.5), greaterThan(.005));
        expect(
          rms(difference, .70, .85),
          greaterThan(.005),
          reason: 'original pop contributes to decoded AAC',
        );
        expect(
          rms(difference, 1.05, 1.2),
          lessThan(.006),
          reason: 'no delayed SFX after clip ends',
        );
        debugPrint(
          'V3_AUDIO_CHECK rms=${rms(audio, 0, 1.5)} popDifference=${rms(difference, .70, .85)} outsideDifference=${rms(difference, 1.05, 1.2)}',
        );

        final before = await File(output).readAsBytes();
        final cancelled = VideoExporter();
        await expectLater(
          cancelled.export(project, output, (value) {
            if (value > .2) cancelled.cancel();
          }),
          throwsA(isA<ExportCancelled>()),
        );
        expect(await File(output).readAsBytes(), orderedEquals(before));
        expect(await File('$output.previous').exists(), isFalse);
        final lateCancel = VideoExporter();
        await expectLater(
          lateCancel.export(project, output, (value) {
            if (value >= .98) lateCancel.cancel();
          }),
          throwsA(isA<ExportCancelled>()),
        );
        expect(await File(output).readAsBytes(), orderedEquals(before));
        expect(await File('$output.tve-pending').exists(), isFalse);

        final oldFile = File('$root/demo/Pulse.tve');
        final oldBytes = await oldFile.readAsBytes();
        expect((jsonDecode(utf8.decode(oldBytes)) as Map)['version'], 1);
        final old = await ProjectStore.read(oldFile.path);
        expect(old.audioClips, isEmpty);
        expect(old.globalEffects, isEmpty);
        expect(old.frameRate, 30);
        expect(await oldFile.readAsBytes(), orderedEquals(oldBytes));
        debugPrint(
          'V3_NATIVE_EXPORT_PASS H264/AAC 854x480 24fps 36frames 1.5s; preview/global/transition/overlay/caption/audio/cancel/v1 verified',
        );
      } finally {
        if (temp.absolute.path != ownPath ||
            !temp.path
                .split(Platform.pathSeparator)
                .last
                .startsWith('tve_v3_export_check_')) {
          throw StateError(
            'Refusing cleanup outside the created test directory',
          );
        }
        if (await temp.exists()) await temp.delete(recursive: true);
      }
    });
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  }, timeout: const Timeout(Duration(minutes: 5)));
}
