import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'media_bridge.dart';
import 'model.dart';

const _rate = 48000;
const _chunkFrames = 4096;

/// Android output-channel masks use increasing bit order. Without a mask use
/// conventional mono, stereo, quad, 5.1 and 7.1 layouts; normalize each side.
({List<double> left, List<double> right}) pcmStereoWeights(
  int channels, {
  int channelMask = 0,
}) {
  if (channels < 1 || channels > 8) throw const FormatException('PCM channels');
  if (channels == 1) return (left: [1], right: [1]);
  const layouts = <List<int>>[
    [],
    [],
    [4, 8],
    [4, 8, 16],
    [4, 8, 64, 128],
    [4, 8, 16, 64, 128],
    [4, 8, 16, 32, 64, 128],
    [4, 8, 16, 32, 1024, 2048, 4096],
    [4, 8, 16, 32, 64, 128, 2048, 4096],
  ];
  final masked = [
    for (var bit = 4; bit <= 1 << 27; bit <<= 1)
      if (channelMask & bit != 0) bit,
  ];
  final layout = masked.length == channels ? masked : layouts[channels];
  final left = <double>[], right = <double>[];
  for (final channel in layout) {
    left.add(switch (channel) {
      4 => 1,
      8 || 128 || 512 || 4096 => 0,
      16 || 64 || 256 || 2048 => math.sqrt1_2,
      _ => .5,
    });
    right.add(switch (channel) {
      8 => 1,
      4 || 64 || 256 || 2048 => 0,
      16 || 128 || 512 || 4096 => math.sqrt1_2,
      _ => .5,
    });
  }
  final leftSum = left.reduce((a, b) => a + b),
      rightSum = right.reduce((a, b) => a + b);
  return (
    left: left.map((w) => w / math.max(1, leftSum)).toList(),
    right: right.map((w) => w / math.max(1, rightSum)).toList(),
  );
}

class AudioMixCancelled implements Exception {
  @override
  String toString() => 'Подготовка звука отменена';
}

/// Offline stereo WAV of the selected project trim, starting at time zero.
/// Decoders write bounded PCM chunks to disk; accumulation runs off the UI isolate.
Future<String> prepareAudioMix(
  Project project,
  Directory temp,
  void Function(double) progress,
  bool Function() cancelled,
) async {
  void check() {
    if (cancelled()) throw AudioMixCancelled();
  }

  check();
  final frames =
      (project.totalFrames * _rate + project.frameRate - 1) ~/
      project.frameRate;
  if (frames <= 0 || frames * 4 > 0xffffffff - 36) {
    throw const FormatException('Недопустимая длительность WAV (лимит 4 ГБ)');
  }
  final work = await temp.createTemp('audio_mix_');
  final output = File('${work.path}/mix.wav');
  final scratch = File('${work.path}/accumulation.f32');
  final cancelFile = File('${work.path}/cancel');
  var succeeded = false;
  Process? process;
  var cancelSent = false;
  final timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
    if (cancelled() && !cancelSent) {
      cancelSent = true;
      cancelFile.writeAsStringSync('cancel');
      process?.kill();
      if (Platform.isAndroid) {
        unawaited(nativeMedia.invokeMethod('cancelAudioDecode'));
      }
    }
  });
  try {
    final accumulator = scratch.openSync(mode: FileMode.write);
    try {
      accumulator.truncateSync(frames * 8);
    } finally {
      accumulator.closeSync();
    }
    final clips = [
      if (project.audio != null && project.musicVolume > 0)
        AudioClip(
          id: 'main',
          path: project.audio!,
          durationUs: project.durationUs,
          group: 'music',
        ),
      ...project.audioClips.where((clip) => clip.enabled && clip.volume > 0),
    ];
    final renderEnd = project.startUs + (frames * 1000000 + _rate - 1) ~/ _rate;
    for (var index = 0; index < clips.length; index++) {
      check();
      final clip = clips[index];
      clip.validate();
      final gain = clip.group == 'music'
          ? project.musicVolume
          : project.soundVolume;
      if (!gain.isFinite || gain < 0 || gain > 2) {
        throw const FormatException('Некорректная громкость группы');
      }
      final from = math.max(project.startUs, clip.startUs);
      final to = math.min(renderEnd, clip.endUs);
      if (from >= to || gain == 0) continue;
      final decoded = File('${work.path}/source.pcm');
      var sampleRate = _rate, channels = 2, sampleBytes = 2, channelMask = 0;
      var floating = false;
      try {
        final sourceStart = clip.sourceStartUs + from - clip.startUs;
        if (Platform.isAndroid) {
          final metadata = await nativeMedia.invokeMapMethod<String, dynamic>(
            'decodeAudioPcm',
            {
              'path': clip.path,
              'output': decoded.path,
              'startUs': sourceStart,
              'durationUs': to - from,
            },
          );
          if (metadata == null) throw StateError('Декодер не вернул PCM');
          sampleRate = (metadata['sampleRate'] as num).toInt();
          channels = (metadata['channels'] as num).toInt();
          channelMask = (metadata['channelMask'] as num?)?.toInt() ?? 0;
          floating = metadata['floatPcm'] == true;
          sampleBytes = floating ? 4 : 2;
        } else {
          process = await Process.start(mediaTool('ffmpeg'), [
            '-v',
            'error',
            '-nostdin',
            '-y',
            '-ss',
            '${sourceStart / 1000000}',
            '-i',
            clip.path,
            '-t',
            '${(to - from) / 1000000}',
            '-vn',
            '-ac',
            '2',
            '-ar',
            '$_rate',
            '-f',
            's16le',
            decoded.path,
          ]);
          var errors = '';
          final errorSub = process.stderr.transform(utf8.decoder).listen((s) {
            errors = errors + s;
            if (errors.length > 8000) {
              errors = errors.substring(errors.length - 8000);
            }
          });
          final outputSub = process.stdout.drain<void>();
          final code = await process.exitCode;
          await outputSub;
          await errorSub.cancel();
          process = null;
          check();
          if (code != 0) throw StateError('Декодирование звука: $errors');
        }
        check();
        if (sampleRate < 8000 ||
            sampleRate > 384000 ||
            channels < 1 ||
            channels > 8) {
          throw const FormatException('Неподдерживаемый формат PCM');
        }
        final decodeRate = sampleRate,
            decodeChannels = channels,
            decodeBytes = sampleBytes,
            decodeFloat = floating,
            decodeMask = channelMask;
        await Isolate.run(
          () => _accumulate(
            scratch.path,
            decoded.path,
            frames,
            project.startUs,
            from,
            to,
            clip,
            gain,
            decodeRate,
            decodeChannels,
            decodeBytes,
            decodeFloat,
            decodeMask,
            cancelFile.path,
          ),
        );
      } finally {
        if (await decoded.exists()) await decoded.delete();
      }
      progress(.9 * (index + 1) / math.max(1, clips.length));
    }
    check();
    await Isolate.run(
      () => _writeWave(scratch.path, output.path, frames, cancelFile.path),
    );
    check();
    await scratch.delete();
    progress(1);
    succeeded = true;
    return output.path;
  } catch (_) {
    check();
    rethrow;
  } finally {
    timer.cancel();
    process?.kill();
    if (!succeeded && await work.exists()) await work.delete(recursive: true);
  }
}

void _checkCancel(String path) {
  if (File(path).existsSync()) throw AudioMixCancelled();
}

void _accumulate(
  String scratchPath,
  String inputPath,
  int totalFrames,
  int projectStartUs,
  int fromUs,
  int toUs,
  AudioClip clip,
  double groupGain,
  int sampleRate,
  int channels,
  int sampleBytes,
  bool floating,
  int channelMask,
  String cancelPath,
) {
  final input = File(inputPath).openSync();
  final output = File(scratchPath).openSync(mode: FileMode.append);
  // append preserves the file and sets only the initial position to its end.
  try {
    final inputFrames = input.lengthSync() ~/ (channels * sampleBytes);
    final weights = pcmStereoWeights(channels, channelMask: channelMask);
    final first = ((fromUs - projectStartUs) * _rate + 999999) ~/ 1000000;
    final end = math.min(
      totalFrames,
      ((toUs - projectStartUs) * _rate + 999999) ~/ 1000000,
    );
    for (var frame = first; frame < end; frame += _chunkFrames) {
      _checkCancel(cancelPath);
      final count = math.min(_chunkFrames, end - frame);
      final firstPosition =
          (projectStartUs + frame * 1000000 / _rate - fromUs) *
          sampleRate /
          1000000;
      final sourceFirst = math.max(0, firstPosition.floor());
      final sourceEnd = math.min(
        inputFrames,
        (firstPosition + count * sampleRate / _rate).ceil() + 1,
      );
      if (sourceFirst >= sourceEnd) continue;
      input.setPositionSync(sourceFirst * channels * sampleBytes);
      final source = ByteData.sublistView(
        input.readSync((sourceEnd - sourceFirst) * channels * sampleBytes),
      );
      output.setPositionSync(frame * 8);
      final sum = ByteData.sublistView(output.readSync(count * 8));
      output.setPositionSync(frame * 8);
      double value(int sourceFrame, int side) {
        if (sourceFrame < sourceFirst || sourceFrame >= sourceEnd) return 0;
        final gains = side == 0 ? weights.left : weights.right;
        var result = 0.0;
        for (var channel = 0; channel < channels; channel++) {
          if (gains[channel] == 0) continue;
          final offset =
              ((sourceFrame - sourceFirst) * channels + channel) * sampleBytes;
          final sample = floating
              ? source.getFloat32(offset, Endian.little)
              : source.getInt16(offset, Endian.little) / 32768;
          if (sample.isFinite) result += sample * gains[channel];
        }
        return result;
      }

      for (var local = 0; local < count; local++) {
        final position = firstPosition + local * sampleRate / _rate;
        final low = position.floor(), fraction = position - position.floor();
        final timeUs = projectStartUs + (frame + local) * 1000000 ~/ _rate;
        final gain = clip.gainAt(timeUs) * groupGain;
        for (var side = 0; side < 2; side++) {
          final sample =
              value(low, side) * (1 - fraction) +
              value(low + 1, side) * fraction;
          final offset = (local * 2 + side) * 4;
          sum.setFloat32(
            offset,
            sum.getFloat32(offset, Endian.little) + sample * gain,
            Endian.little,
          );
        }
      }
      output.writeFromSync(sum.buffer.asUint8List());
    }
  } finally {
    input.closeSync();
    output.closeSync();
  }
}

void _writeWave(
  String scratchPath,
  String outputPath,
  int frames,
  String cancelPath,
) {
  final input = File(scratchPath).openSync();
  final output = File(outputPath).openSync(mode: FileMode.write);
  try {
    final header = ByteData(44);
    void tag(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        header.setUint8(offset + i, value.codeUnitAt(i));
      }
    }

    tag(0, 'RIFF');
    tag(8, 'WAVE');
    tag(12, 'fmt ');
    tag(36, 'data');
    header.setUint32(4, 36 + frames * 4, Endian.little);
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, 2, Endian.little);
    header.setUint32(24, _rate, Endian.little);
    header.setUint32(28, _rate * 4, Endian.little);
    header.setUint16(32, 4, Endian.little);
    header.setUint16(34, 16, Endian.little);
    header.setUint32(40, frames * 4, Endian.little);
    output.writeFromSync(header.buffer.asUint8List());
    for (var frame = 0; frame < frames; frame += _chunkFrames) {
      _checkCancel(cancelPath);
      final count = math.min(_chunkFrames, frames - frame);
      final source = ByteData.sublistView(input.readSync(count * 8));
      final pcm = ByteData(count * 4);
      for (var sample = 0; sample < count * 2; sample++) {
        final value = source.getFloat32(sample * 4, Endian.little);
        pcm.setInt16(
          sample * 2,
          (value.clamp(-1.0, 32767 / 32768) * 32768).round(),
          Endian.little,
        );
      }
      output.writeFromSync(pcm.buffer.asUint8List());
    }
  } finally {
    input.closeSync();
    output.closeSync();
  }
}
