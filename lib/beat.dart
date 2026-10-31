import 'dart:math' as math;

/// Offline amplitude-onset analysis. Times remain in the full source timeline.
class BeatAnalysis {
  final List<int> timesUs;
  final double? bpm;

  BeatAnalysis({required List<int> timesUs, this.bpm})
    : timesUs = List.unmodifiable(timesUs);
}

/// Finds prominent local peaks in uniformly sampled nonnegative RMS/peak data.
///
/// Sample i represents the start of bucket i: i * durationUs / sampleCount.
/// Higher sensitivity admits quieter peaks. Closely spaced peaks (180 ms) are
/// merged, keeping the strongest. No beat grid is synthesized or trim applied.
/// BPM is null when fewer than three onsets or no consistent tempo is observed.
BeatAnalysis detectBeats(
  List<double> envelope,
  int durationUs, {
  double sensitivity = .5,
}) {
  if (durationUs < 0) {
    throw ArgumentError.value(durationUs, 'durationUs', 'Must be nonnegative');
  }
  if (!sensitivity.isFinite || sensitivity < 0 || sensitivity > 1) {
    throw ArgumentError.value(sensitivity, 'sensitivity', 'Must be in 0..1');
  }
  var maximum = 0.0;
  for (final value in envelope) {
    if (!value.isFinite || value < 0) {
      throw ArgumentError.value(
        value,
        'envelope',
        'Must be finite and nonnegative',
      );
    }
    maximum = math.max(maximum, value);
  }
  if (durationUs == 0 || maximum == 0 || envelope.length < 3) {
    return BeatAnalysis(timesUs: const []);
  }

  // Normalizing first also prevents overflow for very large finite amplitudes.
  final values = [for (final value in envelope) value / maximum];
  final prefix = <double>[0];
  for (final value in values) {
    prefix.add(prefix.last + value);
  }
  final radius = math.max(1, (250000 * values.length / durationUs).round());
  final floor = .45 - .37 * sensitivity;
  final contrast = 2 - .65 * sensitivity;
  final candidates = <int>[];
  for (var i = 0; i < values.length; i++) {
    final value = values[i];
    if (value < floor ||
        (i > 0 && value < values[i - 1]) ||
        (i + 1 < values.length && value <= values[i + 1])) {
      continue;
    }
    final start = math.max(0, i - radius);
    final end = math.min(values.length, i + radius + 1);
    final mean = (prefix[end] - prefix[start]) / (end - start);
    if (value <= mean * contrast) continue;
    if (candidates.isNotEmpty &&
        (i - candidates.last) * durationUs / values.length < 180000) {
      if (value > values[candidates.last]) {
        candidates[candidates.length - 1] = i;
      }
    } else {
      candidates.add(i);
    }
  }
  final times = <int>[];
  for (final index in candidates) {
    final time = (index * durationUs / values.length).round();
    if (times.isEmpty || time > times.last) times.add(time);
  }
  return BeatAnalysis(timesUs: times, bpm: _estimateBpm(times));
}

double? _estimateBpm(List<int> times) {
  if (times.length < 3) return null;
  final intervals = <int>[
    for (var i = 1; i < times.length; i++) times[i] - times[i - 1],
  ]..sort();
  final median = intervals[intervals.length ~/ 2];
  // ponytail: amplitude onsets cannot disambiguate half/double-time musical beat.
  // Keep the observed pulse tempo instead of inventing or correcting a beat grid.
  if (median < 250000 || median > 2000000) return null;
  final consistent = intervals
      .where((interval) => (interval - median).abs() <= median * .2)
      .toList();
  if (consistent.length < 2 || consistent.length / intervals.length < .6) {
    return null;
  }
  return 60000000 / (consistent.reduce((a, b) => a + b) / consistent.length);
}
