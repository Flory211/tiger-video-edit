import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tiger_video_edit/audio_mixer.dart';
import 'package:tiger_video_edit/model.dart';

Future<File> constantWave(Directory dir, String name, int value) async {
  const frames = 96000;
  final bytes = ByteData(44 + frames * 4);
  void tag(int offset, String text) {
    for (var i = 0; i < text.length; i++) {
      bytes.setUint8(offset + i, text.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  tag(36, 'data');
  bytes.setUint32(4, bytes.lengthInBytes - 8, Endian.little);
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, 2, Endian.little);
  bytes.setUint32(24, 48000, Endian.little);
  bytes.setUint32(28, 192000, Endian.little);
  bytes.setUint16(32, 4, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  bytes.setUint32(40, frames * 4, Endian.little);
  for (var i = 44; i < bytes.lengthInBytes; i += 2) {
    bytes.setInt16(i, value, Endian.little);
  }
  return File('${dir.path}/$name').writeAsBytes(bytes.buffer.asUint8List());
}

void main() {
  test('surround downmix retains center, bass and rear channels', () {
    final weights = pcmStereoWeights(6);
    expect(weights.left.length, 6);
    expect(weights.left[2], greaterThan(0));
    expect(weights.right[2], greaterThan(0));
    expect(weights.left[3], greaterThan(0));
    expect(weights.left[4], greaterThan(0));
    expect(weights.right[5], greaterThan(0));
    expect(weights.left.reduce((a, b) => a + b), closeTo(1, 1e-10));
    expect(pcmStereoWeights(1).left, [1]);
  });
  test(
    'actual decoded mix preserves project trim, group volume and fades',
    () async {
      final temp = await Directory.systemTemp.createTemp('tve_mix_test_');
      try {
        final main = await constantWave(temp, 'music.wav', 4000);
        final sound = await constantWave(temp, 'sfx.wav', 4000);
        final project = Project(
          audio: main.path,
          frameRate: 24,
          durationUs: 2000000,
          startUs: 500000,
          endUs: 1500000,
          musicVolume: .5,
          soundVolume: .5,
          audioClips: [
            AudioClip(
              id: 'sfx',
              path: sound.path,
              startUs: 750000,
              durationUs: 500000,
              volume: .5,
              fadeInUs: 250000,
              fadeOutUs: 250000,
            ),
          ],
        );
        final output = await prepareAudioMix(
          project,
          temp,
          (_) {},
          () => false,
        );
        final bytes = ByteData.sublistView(await File(output).readAsBytes());
        expect(bytes.getUint32(24, Endian.little), 48000);
        expect(bytes.getUint32(40, Endian.little), 48000 * 4);
        int sample(double seconds) =>
            bytes.getInt16(44 + (seconds * 48000).round() * 4, Endian.little);
        expect(sample(.1), closeTo(2000, 3));
        expect(sample(.375), closeTo(2500, 3));
        expect(sample(.5), closeTo(3000, 3));
        expect(sample(.625), closeTo(2500, 3));
        expect(sample(.9), closeTo(2000, 3));
        final sixty = await prepareAudioMix(
          project.copy(frameRate: 60),
          temp,
          (_) {},
          () => false,
        );
        final sixtyBytes = ByteData.sublistView(
          await File(sixty).readAsBytes(),
        );
        expect(sixtyBytes.getUint32(40, Endian.little), 48000 * 4);
      } finally {
        await temp.delete(recursive: true);
      }
    },
  );

  test('cancelled mix leaves caller files intact and no partial mix', () async {
    final temp = await Directory.systemTemp.createTemp('tve_mix_cancel_');
    try {
      final source = await constantWave(temp, 'music.wav', 1000);
      final sentinel = await File('${temp.path}/keep.txt')
          .writeAsString('keep');
      await expectLater(
        prepareAudioMix(
          Project(audio: source.path, durationUs: 2000000, endUs: 1000000),
          temp,
          (_) {},
          () => true,
        ),
        throwsA(isA<AudioMixCancelled>()),
      );
      expect(await sentinel.readAsString(), 'keep');
      expect(temp.listSync().whereType<Directory>(), isEmpty);
    } finally {
      await temp.delete(recursive: true);
    }
  });

  test(
    'mix clips only after summing tracks and respects source offset',
    () async {
      final temp = await Directory.systemTemp.createTemp('tve_mix_sum_');
      try {
        final positive = await constantWave(temp, 'positive.wav', 22000);
        final negative = await constantWave(temp, 'negative.wav', -22000);
        final bytes = await positive.readAsBytes();
        final data = ByteData.sublistView(bytes);
        for (var offset = 44; offset < 44 + 48000 * 4; offset += 2) {
          data.setInt16(offset, 1000, Endian.little);
        }
        await positive.writeAsBytes(bytes);
        final project = Project(
          durationUs: 1000000,
          endUs: 1000000,
          audioClips: [
            for (var i = 0; i < 2; i++)
              AudioClip(
                id: 'positive$i',
                path: positive.path,
                sourceStartUs: 1000000,
                durationUs: 1000000,
              ),
            AudioClip(id: 'negative', path: negative.path, durationUs: 1000000),
          ],
        );
        final output = await prepareAudioMix(
          project,
          temp,
          (_) {},
          () => false,
        );
        final wave = ByteData.sublistView(await File(output).readAsBytes());
        expect(wave.getInt16(44 + 10000 * 4, Endian.little), closeTo(22000, 3));
        expect(
          wave.getInt16(44 + 10000 * 4 + 2, Endian.little),
          closeTo(22000, 3),
        );
      } finally {
        await temp.delete(recursive: true);
      }
    },
  );

  test('cancellation after decoding removes intermediate files', () async {
    final temp = await Directory.systemTemp.createTemp('tve_mix_mid_cancel_');
    try {
      final source = await constantWave(temp, 'music.wav', 1000);
      var cancel = false;
      await expectLater(
        prepareAudioMix(
          Project(audio: source.path, durationUs: 2000000, endUs: 1000000),
          temp,
          (_) {
            cancel = true;
          },
          () => cancel,
        ),
        throwsA(isA<AudioMixCancelled>()),
      );
      expect(temp.listSync().whereType<Directory>(), isEmpty);
      expect(await source.exists(), isTrue);
    } finally {
      await temp.delete(recursive: true);
    }
  });
}
