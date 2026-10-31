import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:media_kit/media_kit.dart';

import 'model.dart';
import 'media_bridge.dart';
import 'compositor.dart';
import 'media_frames.dart';
import 'audio_mixer.dart';
export 'media_bridge.dart';
export 'compositor.dart' show paintStill, paintFrame, VisualFrame;

class AudioEngine {
  final Player player = Player();
  Future<int> positionUs() async {
    final native = player.platform;
    if (native is NativePlayer) {
      final seconds = double.tryParse(await native.getProperty('time-pos'));
      if (seconds != null) return (seconds * 1000000).round();
    }
    return player.state.position.inMicroseconds;
  }

  Future<int> open(String path) async {
    await player.open(Media(path), play: false);
    if (player.state.duration > Duration.zero) {
      return player.state.duration.inMicroseconds;
    }
    final value = await player.stream.duration
        .firstWhere((d) => d > Duration.zero)
        .timeout(
          const Duration(seconds: 20),
          onTimeout: () =>
              throw const FormatException('Не удалось декодировать аудио'),
        );
    return value.inMicroseconds;
  }
}

Future<ui.Image> decodeStill(String path) async {
  final bytes = await File(path).readAsBytes();
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}

final previewImages = PreviewImageCache();

class PreviewImageCache {
  final _images = <String, ui.Image>{};
  final _pending = <String, Future<ui.Image>>{};
  ui.Image? peek(String path) => _images[path];
  Future<ui.Image> load(String path) async {
    final cached = _images[path];
    if (cached != null) return cached;
    final pending = _pending[path];
    if (pending != null) return pending;
    final task = _decode(path);
    _pending[path] = task;
    try {
      final image = await task;
      _images[path] = image;
      // Bounded to 16 screen-resolution images; active widgets own clones.
      while (_images.length > 16) {
        final first = _images.keys.first;
        _images.remove(first)!.dispose();
      }
      return image;
    } finally {
      _pending.remove(path);
    }
  }

  Future<ui.Image> _decode(String path) async {
    final buffer = await ui.ImmutableBuffer.fromFilePath(path);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    try {
      final factor = math.min(
        1.0,
        1920 / math.max(descriptor.width, descriptor.height),
      );
      final codec = await descriptor.instantiateCodec(
        targetWidth: math.max(1, (descriptor.width * factor).round()),
        targetHeight: math.max(1, (descriptor.height * factor).round()),
      );
      try {
        return (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
    } finally {
      descriptor.dispose();
      buffer.dispose();
    }
  }

  Future<void> prepare(Iterable<String> paths) async {
    for (final path in paths.toSet().take(16)) {
      await load(path);
    }
  }
}

Future<void> renderStill(
  Still still,
  String path,
  int width,
  int height,
) async {
  final image = await decodeStill(still.path);
  final recorder = ui.PictureRecorder();
  paintStill(
    ui.Canvas(recorder),
    ui.Size(width.toDouble(), height.toDouble()),
    image,
    still,
  );
  final picture = recorder.endRecording();
  final output = await picture.toImage(width, height);
  try {
    final bytes = await output.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) throw StateError('Не удалось подготовить изображение');
    await File(path).writeAsBytes(bytes.buffer.asUint8List());
  } finally {
    image.dispose();
    picture.dispose();
    output.dispose();
  }
}

Future<List<double>> waveform(
  String path,
  int durationUs, {
  int bins = 2000,
}) async {
  if (Platform.isAndroid) {
    final values = await nativeMedia.invokeListMethod<num>('waveform', {
      'path': path,
      'durationUs': durationUs,
      'bins': bins,
    });
    return values!.map((e) => e.toDouble()).toList();
  }
  // Bounded output: 1200 signed 16-bit samples per second, aggregated into 2000 bins.
  final process = await Process.start(mediaTool('ffmpeg'), [
    '-v',
    'error',
    '-i',
    path,
    '-vn',
    '-ac',
    '1',
    '-ar',
    '1200',
    '-f',
    's16le',
    'pipe:1',
  ]);
  final error = process.stderr.transform(utf8.decoder).join();
  final peaks = List<double>.filled(bins, 0);
  final count = math.max(1, (durationUs * 1200 / 1000000).ceil());
  var sample = 0;
  int? low;
  await for (final chunk in process.stdout) {
    for (final b in chunk) {
      if (low == null) {
        low = b;
        continue;
      }
      var value = low | (b << 8);
      low = null;
      if (value >= 32768) value -= 65536;
      final index = math.min(bins - 1, sample++ * bins ~/ count);
      peaks[index] = math.max(peaks[index], value.abs() / 32768);
    }
  }
  if (await process.exitCode != 0) {
    throw FormatException('Ошибка звуковой волны: ${await error}');
  }
  return peaks;
}

class ExportCancelled implements Exception {
  @override
  String toString() => 'Экспорт отменён';
}

class VideoExporter {
  Process? _process;
  bool _cancelled = false;
  bool _running = false;
  void cancel() {
    _cancelled = true;
    _process?.kill();
    if (Platform.isAndroid) unawaited(nativeMedia.invokeMethod('cancel'));
  }

  void _check() {
    if (_cancelled) throw ExportCancelled();
  }

  Future<void> _run(
    List<String> args,
    void Function(double)? onProgress,
    int frames,
  ) async {
    _check();
    final proc = await Process.start(mediaTool('ffmpeg'), [
      '-hide_banner',
      '-loglevel',
      'error',
      '-nostdin',
      '-y',
      ...args,
      '-progress',
      'pipe:1',
    ]);
    _process = proc;
    var errors = '';
    final errorSub = proc.stderr.transform(utf8.decoder).listen((s) {
      errors = (errors + s);
      if (errors.length > 12000) {
        errors = errors.substring(errors.length - 12000);
      }
    });
    final progressSub = proc.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          if (line.startsWith('frame=')) {
            final frame = int.tryParse(line.substring(6).trim()) ?? 0;
            onProgress?.call((frame / math.max(1, frames)).clamp(0, 1));
          }
        });
    final code = await proc.exitCode;
    await errorSub.cancel();
    await progressSub.cancel();
    _process = null;
    _check();
    if (code != 0) throw StateError('FFmpeg: $errors');
  }

  Future<void> export(
    Project p,
    String destination,
    void Function(double) progress,
  ) async {
    if (_running) throw StateError('Экспорт уже выполняется');
    _running = true;
    _cancelled = false;
    Directory? temp;
    try {
      p.validate();
      final rate = p.frameRate;
      if (p.audio == null || p.images.isEmpty || p.totalFrames <= 0) {
        throw StateError('Добавьте музыку и изображения');
      }
      temp = await Directory.systemTemp.createTemp('tiger_render_');
      var inputAudio = p.audio!, audioStart = p.startUs;
      if (p.audioClips.isNotEmpty || p.musicVolume != 1 || p.soundVolume != 1) {
        inputAudio = await prepareAudioMix(
          p,
          temp,
          (v) => progress(v * .05),
          () => _cancelled,
        );
        audioStart = 0;
      }
      final staged = '${temp.path}/result.mp4';
      final inputs = <({String path, int frames})>[];
      final animated = p.needsFrameRendering;
      if (animated) {
        final source = MediaFrameSource(
          maxDimension: math.max(p.width, p.height),
        );
        final schedule = p.segments;
        var segmentIndex = 0;
        ui.Image? previousImage;
        Still? previousItem;
        var previousSegment = -1;
        final previousSource = MediaFrameSource(
          maxDimension: math.max(p.width, p.height),
        );
        final overlaySources = <String, MediaFrameSource>{};
        try {
          for (var frame = 0; frame < p.totalFrames; frame++) {
            _check();
            while (segmentIndex + 1 < schedule.length &&
                schedule[segmentIndex + 1].startFrame <= frame) {
              segmentIndex++;
            }
            final segment = schedule[segmentIndex],
                item = p.images[segment.imageIndex];
            final localUs =
                ((frame - segment.startFrame) * 1000000 + rate - 1) ~/ rate;
            final sourceUs = p.startUs + frame * 1000000 ~/ rate;
            if (previousSegment != segmentIndex) {
              previousSegment = segmentIndex;
              previousImage?.dispose();
              previousImage = null;
              previousItem = null;
              if (segmentIndex > 0) {
                final prev = schedule[segmentIndex - 1];
                previousItem = p.images[prev.imageIndex];
                previousImage = await previousSource.frame(
                  previousItem,
                  (prev.frameCount - 1) * 1000000 ~/ rate,
                );
              }
            }
            final image = await source.frame(item, localUs);
            final active =
                p.visualClips.where((c) => c.activeAt(sourceUs)).toList()
                  ..sort((a, b) => a.track.compareTo(b.track));
            final overlayFrames = <VisualFrame>[];
            for (final c in active) {
              final decoder = overlaySources.putIfAbsent(
                c.id,
                () =>
                    MediaFrameSource(maxDimension: math.max(p.width, p.height)),
              );
              overlayFrames.add(
                VisualFrame(
                  c.media,
                  await decoder.frame(c.media, sourceUs - c.startUs),
                  sourceUs - c.startUs,
                  c.opacity,
                ),
              );
            }
            for (final id
                in overlaySources.keys
                    .where((id) => !active.any((c) => c.id == id))
                    .toList()) {
              await overlaySources.remove(id)!.dispose();
            }
            final recorder = ui.PictureRecorder();
            paintFrame(
              ui.Canvas(recorder),
              ui.Size(p.width.toDouble(), p.height.toDouble()),
              image,
              item,
              localUs: localUs,
              sourceUs: sourceUs,
              captions: p.captions,
              referenceWidth: p.width.toDouble(),
              project: p,
              previousImage: previousImage,
              previousItem: previousItem,
              overlays: overlayFrames,
            );
            final picture = recorder.endRecording();
            final output = await picture.toImage(p.width, p.height);
            try {
              final data = await output.toByteData(
                format: ui.ImageByteFormat.png,
              );
              if (data == null) throw StateError('Не удалось подготовить кадр');
              final path =
                  '${temp.path}/frame_${frame.toString().padLeft(8, '0')}.png';
              await File(path).writeAsBytes(data.buffer.asUint8List());
              inputs.add((path: path, frames: 1));
            } finally {
              image.dispose();
              picture.dispose();
              output.dispose();
              for (final overlay in overlayFrames) {
                overlay.image.dispose();
              }
            }
            progress(.65 * (frame + 1) / p.totalFrames);
          }
        } finally {
          await source.dispose();
          previousImage?.dispose();
          await previousSource.dispose();
          for (final decoder in overlaySources.values) {
            await decoder.dispose();
          }
        }
      } else {
        final frames = <String>[];
        for (var i = 0; i < p.images.length; i++) {
          _check();
          final path = '${temp.path}/still_$i.png';
          await renderStill(p.images[i], path, p.width, p.height);
          frames.add(path);
          progress(.1 * (i + 1) / p.images.length);
        }
        for (final segment in p.segments) {
          inputs.add((
            path: frames[segment.imageIndex],
            frames: segment.frameCount,
          ));
        }
      }
      if (Platform.isAndroid) {
        await nativeMedia.invokeMethod('startExport', {
          'audio': inputAudio,
          'startUs': audioStart,
          'durationUs': p.totalFrames * 1000000 ~/ rate,
          'fps': rate,
          'videoBitrate':
              (p.width *
                      p.height *
                      rate *
                      (p.videoCrf <= 16
                          ? 0.18
                          : p.videoCrf <= 22
                          ? 0.12
                          : 0.07))
                  .round()
                  .clamp(500000, 50000000),
          'width': p.width,
          'height': p.height,
          'output': staged,
          'segments': [
            for (final input in inputs)
              {'path': input.path, 'frames': input.frames},
          ],
        });
        while (true) {
          _check();
          final state = await nativeMedia.invokeMapMethod<String, dynamic>(
            'exportStatus',
          );
          if (state?['error'] != null) {
            throw StateError(state!['error'] as String);
          }
          progress(
            (animated ? .65 : .1) +
                (animated ? .3 : .85) *
                    ((state?['progress'] as num?)?.toDouble() ?? 0),
          );
          if (state?['done'] == true) break;
          await Future<void>.delayed(const Duration(milliseconds: 120));
        }
      } else if (animated) {
        await _run(
          [
            '-framerate',
            '$rate',
            '-i',
            '${temp.path}/frame_%08d.png',
            '-ss',
            '${audioStart / 1000000}',
            '-i',
            inputAudio,
            '-map',
            '0:v:0',
            '-map',
            '1:a:0',
            '-frames:v',
            '${p.totalFrames}',
            '-c:v',
            'libx264',
            '-preset',
            'veryfast',
            '-crf',
            '${p.videoCrf}',
            '-pix_fmt',
            'yuv420p',
            '-c:a',
            'aac',
            '-b:a',
            '192k',
            '-af',
            'apad',
            '-t',
            '${p.totalFrames / rate}',
            '-movflags',
            '+faststart',
            staged,
          ],
          (value) => progress(.65 + .3 * value),
          p.totalFrames,
        );
        await validateVideo(staged, p.totalFrames / rate);
      } else {
        var completed = 0;
        for (var i = 0; i < inputs.length; i++) {
          final input = inputs[i];
          await _run(
            [
              '-loop',
              '1',
              '-framerate',
              '$rate',
              '-i',
              input.path,
              '-frames:v',
              '${input.frames}',
              '-an',
              '-c:v',
              'libx264',
              '-preset',
              'veryfast',
              '-crf',
              '${p.videoCrf}',
              '-pix_fmt',
              'yuv420p',
              '-r',
              '$rate',
              '${temp.path}/segment_$i.mp4',
            ],
            (value) => progress(
              .1 + .75 * (completed + value * input.frames) / p.totalFrames,
            ),
            input.frames,
          );
          completed += input.frames;
        }
        final list = File('${temp.path}/segments.txt');
        await list.writeAsString(
          [for (var i = 0; i < inputs.length; i++) "file 'segment_$i.mp4'"]
              .join('\n'),
        );
        await _run(
          [
            '-f',
            'concat',
            '-safe',
            '0',
            '-i',
            list.path,
            '-ss',
            '${audioStart / 1000000}',
            '-i',
            inputAudio,
            '-map',
            '0:v:0',
            '-map',
            '1:a:0',
            '-c:v',
            'copy',
            '-c:a',
            'aac',
            '-b:a',
            '192k',
            '-af',
            'apad',
            '-t',
            '${p.totalFrames / rate}',
            '-movflags',
            '+faststart',
            staged,
          ],
          null,
          p.totalFrames,
        );
        await validateVideo(staged, p.totalFrames / rate);
      }
      _check();
      if (!await File(staged).exists() || await File(staged).length() < 100) {
        throw StateError('Экспорт не создал видео');
      }
      progress(0.98);
      if (Platform.isAndroid) {
        final uri = await nativeMedia.invokeMethod<String>('saveVideo', {
          'path': staged,
          'name': destination,
        });
        if (uri == null) throw ExportCancelled();
      } else {
        final pending = File('$destination.tve-pending');
        try {
          await File(staged).copy(pending.path);
          _check();
          final out = File(destination),
              previous = File('$destination.previous');
          // This short metadata commit cannot interleave with cancellation.
          if (previous.existsSync()) previous.deleteSync();
          final existed = out.existsSync();
          if (existed) out.renameSync(previous.path);
          try {
            pending.renameSync(destination);
          } catch (_) {
            if (existed && previous.existsSync() && !out.existsSync()) {
              previous.renameSync(destination);
            }
            rethrow;
          }
        } finally {
          if (await pending.exists()) await pending.delete();
        }
      }
      progress(1);
    } on AudioMixCancelled {
      throw ExportCancelled();
    } finally {
      _running = false;
      _process = null;
      if (temp != null && await temp.exists()) {
        await temp.delete(recursive: true);
      }
    }
  }
}

Future<void> validateVideo(String path, double seconds) async {
  final result = await Process.run(mediaTool('ffprobe'), [
    '-v',
    'error',
    '-show_streams',
    '-show_format',
    '-of',
    'json',
    path,
  ]);
  if (result.exitCode != 0) {
    throw StateError('Не удалось проверить экспортированный файл');
  }
  final json = jsonDecode(result.stdout as String) as Map<String, dynamic>;
  final streams = json['streams'] as List;
  if (!streams.any((s) => s['codec_name'] == 'h264') ||
      !streams.any((s) => s['codec_name'] == 'aac') ||
      ((double.tryParse(json['format']['duration'] as String) ?? 0) - seconds)
              .abs() >
          0.15) {
    throw StateError('Видео не прошло проверку H.264/AAC/продолжительности');
  }
}
