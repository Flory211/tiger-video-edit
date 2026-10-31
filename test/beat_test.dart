import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tiger_video_edit/beat.dart';

void main() {
  test('finds 120 BPM pulses at absolute source positions', () {
    final envelope = List<double>.filled(1000, 0);
    for (var i = 50; i < envelope.length; i += 50) {
      envelope[i] = 1;
      envelope[i + 1] = .6;
      envelope[i + 2] = .2;
    }
    final result = detectBeats(envelope, 10000000);
    expect(result.timesUs, List.generate(19, (i) => (i + 1) * 500000));
    expect(result.bpm, closeTo(120, .01));
  });

  test('does not invent onsets for silence or steady low noise', () {
    final random = Random(42);
    for (final envelope in [
      <double>[],
      List<double>.filled(1000, 0),
      List<double>.filled(1000, .2),
      List.generate(1000, (_) => .01 + random.nextDouble() * .001),
    ]) {
      final result = detectBeats(envelope, 10000000);
      expect(result.timesUs, isEmpty);
      expect(result.bpm, isNull);
    }
  });

  test('increased sensitivity includes quieter isolated pulses', () {
    final envelope = List<double>.filled(300, 0);
    envelope[50] = 1;
    envelope[100] = .2;
    envelope[150] = 1;
    envelope[200] = .2;
    expect(detectBeats(envelope, 3000000, sensitivity: 0).timesUs, [
      500000,
      1500000,
    ]);
    expect(detectBeats(envelope, 3000000, sensitivity: 1).timesUs, [
      500000,
      1000000,
      1500000,
      2000000,
    ]);
  });

  test('nearby peaks collapse to the strongest onset', () {
    final envelope = List<double>.filled(200, 0);
    envelope[50] = .6;
    envelope[55] = 1;
    envelope[100] = 1;
    final result = detectBeats(envelope, 2000000);
    expect(result.timesUs, [550000, 1000000]);
    expect(result.bpm, isNull); // Insufficient evidence for a tempo.
    expect(() => result.timesUs.add(1), throwsUnsupportedError);
  });

  test('BPM tolerates a missing pulse without inserting beats', () {
    final envelope = List<double>.filled(500, 0);
    for (final i in [50, 100, 200, 250, 300, 350, 400]) {
      envelope[i] = 1;
    }
    final result = detectBeats(envelope, 5000000);
    expect(result.timesUs, hasLength(7));
    expect(result.bpm, closeTo(120, .01));
  });

  test('rejects invalid durations, sensitivity and envelope values', () {
    expect(() => detectBeats([1], -1), throwsArgumentError);
    for (final sensitivity in [-.1, 1.1, double.nan, double.infinity]) {
      expect(
        () => detectBeats([0], 100, sensitivity: sensitivity),
        throwsArgumentError,
      );
    }
    for (final value in [-1.0, double.nan, double.infinity]) {
      expect(() => detectBeats([value], 100), throwsArgumentError);
    }
    expect(detectBeats([0, 1], 0).timesUs, isEmpty);
  });

  test(
    'very short and extreme finite inputs never yield NaN or duplicates',
    () {
      for (final envelope in [
        [1.0],
        [0.0, 1.0, 0.0],
        [0.0, double.maxFinite, 0.0, double.maxFinite, 0.0],
      ]) {
        final result = detectBeats(envelope, 1);
        expect(result.timesUs.every((t) => t >= 0 && t <= 1), isTrue);
        expect(result.timesUs.toSet().length, result.timesUs.length);
        expect(result.bpm == null || result.bpm!.isFinite, isTrue);
      }
    },
  );
}
