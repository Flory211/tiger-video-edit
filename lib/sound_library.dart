import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'app_settings.dart';

class SoundEffect {
  final String id, name, path;
  final Duration duration;
  const SoundEffect({
    required this.id,
    required this.name,
    required this.path,
    required this.duration,
  });
}

/// Original procedural synthesis, no samples or third party recordings.
/// Owner distribution license is intentionally not selected by this service.
class SoundLibrary {
  final Directory root;
  SoundLibrary(this.root);
  static const sampleRate = 22050;
  static const licenseNotice =
      'Оригинальные синтезированные звуки Tiger Video Edit. '
      'Лицензия распространения пока не выбрана владельцем проекта.';
  static const _definitions = <(String, String, int)>[
    ('whoosh', 'Whoosh', 650),
    ('impact', 'Impact', 500),
    ('bass_hit', 'Bass Hit', 650),
    ('click', 'Click', 80),
    ('pop', 'Pop', 150),
    ('transition_hit', 'Transition Hit', 750),
    ('riser', 'Riser', 1400),
    ('reverse_whoosh', 'Reverse Whoosh', 700),
    ('glitch', 'Glitch Sound', 350),
    ('boom', 'Cinematic Boom', 1600),
  ];

  Future<List<SoundEffect>> generate() async {
    await root.create(recursive: true);
    final result = <SoundEffect>[];
    for (var kind = 0; kind < _definitions.length; kind++) {
      final (id, name, ms) = _definitions[kind];
      final duration = Duration(milliseconds: ms);
      final file = File('${root.path}/tve-synth-v1-$id.wav');
      final expectedLength =
          44 + duration.inMicroseconds * sampleRate ~/ 1000000 * 2;
      if (!await file.exists() || await file.length() != expectedLength) {
        // Each buffer is bounded to at most 71 KiB.
        await Future<void>(() async {
          await atomicWriteBytes(file, _synthesize(kind, ms));
        });
      }
      result.add(
        SoundEffect(
          id: id,
          name: name,
          path: file.absolute.path,
          duration: duration,
        ),
      );
    }
    return result;
  }

  static Uint8List _synthesize(int kind, int ms) {
    final count = ms * sampleRate ~/ 1000;
    final bytes = ByteData(44 + count * 2);
    void text(int offset, String s) {
      for (var i = 0; i < s.length; i++) {
        bytes.setUint8(offset + i, s.codeUnitAt(i));
      }
    }

    text(0, 'RIFF');
    bytes.setUint32(4, bytes.lengthInBytes - 8, Endian.little);
    text(8, 'WAVE');
    text(12, 'fmt ');
    bytes.setUint32(16, 16, Endian.little);
    bytes.setUint16(20, 1, Endian.little);
    bytes.setUint16(22, 1, Endian.little);
    bytes.setUint32(24, sampleRate, Endian.little);
    bytes.setUint32(28, sampleRate * 2, Endian.little);
    bytes.setUint16(32, 2, Endian.little);
    bytes.setUint16(34, 16, Endian.little);
    text(36, 'data');
    bytes.setUint32(40, count * 2, Endian.little);
    var seed = 0x13579 + kind * 7919;
    var filtered = 0.0;
    for (var i = 0; i < count; i++) {
      final t = i / sampleRate, x = i / count;
      seed = (1664525 * seed + 1013904223) & 0xffffffff;
      final noise = seed / 2147483648 - 1;
      filtered += (noise - filtered) * (0.04 + 0.5 * x);
      final decay = math.exp(-7 * x);
      final tone = math.sin(
        2 * math.pi * (70 * t + 55 * (1 - math.exp(-12 * t)) / 12),
      );
      final value = switch (kind) {
        0 => filtered * math.sin(math.pi * x),
        1 => (noise * 0.45 + tone * 0.55) * decay,
        2 =>
          math.sin(2 * math.pi * (48 * t + 30 * (1 - math.exp(-20 * t)) / 20)) *
              decay,
        3 => noise * math.exp(-25 * x),
        4 => math.sin(2 * math.pi * (500 * t - 800 * t * t)) * math.exp(-9 * x),
        5 => (filtered * 0.65 + tone * 0.35) * math.exp(-5 * x),
        6 =>
          (filtered * 0.6 +
                  math.sin(2 * math.pi * (180 * t + 900 * t * t)) * 0.4) *
              x *
              x,
        7 => filtered * math.pow(x, 2),
        8 =>
          (((i ~/ 110) % 3 == 0 ? noise : math.sin(2 * math.pi * 880 * t)) *
                  0.6) *
              (1 - x),
        _ =>
          (math.sin(
                        2 *
                            math.pi *
                            (35 * t + 25 * (1 - math.exp(-10 * t)) / 10),
                      ) *
                      0.8 +
                  filtered * 0.2) *
              math.exp(-5 * x),
      };
      final fade = math.min(1.0, math.min(i / 110, (count - 1 - i) / 220));
      bytes.setInt16(
        44 + i * 2,
        (value * fade * 0.75 * 32767).round().clamp(-32767, 32767),
        Endian.little,
      );
    }
    return bytes.buffer.asUint8List();
  }
}
