import 'dart:math' as math;

/// An independent source-time audio item. Project trim never changes its source.
class AudioClip {
  final String id, path, group;
  final int startUs, sourceStartUs, durationUs, fadeInUs, fadeOutUs, track;
  final double volume;
  final bool enabled;
  const AudioClip({
    required this.id,
    required this.path,
    this.startUs = 0,
    this.sourceStartUs = 0,
    required this.durationUs,
    this.volume = 1,
    this.fadeInUs = 0,
    this.fadeOutUs = 0,
    this.enabled = true,
    this.track = 0,
    this.group = 'sfx',
  });

  int get endUs => startUs + durationUs;
  double gainAt(int sourceUs) {
    if (!enabled || sourceUs < startUs || sourceUs >= endUs) return 0;
    final local = sourceUs - startUs;
    final fadeIn = fadeInUs == 0 ? 1.0 : (local / fadeInUs).clamp(0.0, 1.0);
    final fadeOut = fadeOutUs == 0
        ? 1.0
        : ((durationUs - local) / fadeOutUs).clamp(0.0, 1.0);
    return volume * math.min(fadeIn, fadeOut);
  }

  void validate() {
    if (id.isEmpty ||
        id.length > 160 ||
        path.isEmpty ||
        path.length > 4096 ||
        startUs < 0 ||
        sourceStartUs < 0 ||
        durationUs <= 0 ||
        durationUs > 86400000000 ||
        startUs > 86400000000 ||
        !volume.isFinite ||
        volume < 0 ||
        volume > 2 ||
        fadeInUs < 0 ||
        fadeInUs > durationUs ||
        fadeOutUs < 0 ||
        fadeOutUs > durationUs ||
        track < 0 ||
        track > 15 ||
        !['sfx', 'music', 'voice'].contains(group)) {
      throw const FormatException('Некорректный аудиоклип');
    }
  }

  AudioClip copy({
    String? id,
    String? path,
    int? startUs,
    int? sourceStartUs,
    int? durationUs,
    double? volume,
    int? fadeInUs,
    int? fadeOutUs,
    bool? enabled,
    int? track,
    String? group,
  }) => AudioClip(
    id: id ?? this.id,
    path: path ?? this.path,
    startUs: startUs ?? this.startUs,
    sourceStartUs: sourceStartUs ?? this.sourceStartUs,
    durationUs: durationUs ?? this.durationUs,
    volume: volume ?? this.volume,
    fadeInUs: fadeInUs ?? this.fadeInUs,
    fadeOutUs: fadeOutUs ?? this.fadeOutUs,
    enabled: enabled ?? this.enabled,
    track: track ?? this.track,
    group: group ?? this.group,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'path': path,
    'startUs': startUs,
    'sourceStartUs': sourceStartUs,
    'durationUs': durationUs,
    'volume': volume,
    'fadeInUs': fadeInUs,
    'fadeOutUs': fadeOutUs,
    'enabled': enabled,
    'track': track,
    'group': group,
  };
  factory AudioClip.fromJson(Map<String, dynamic> j) {
    final clip = AudioClip(
      id: j['id'] as String,
      path: j['path'] as String,
      startUs: j['startUs'] as int? ?? 0,
      sourceStartUs: j['sourceStartUs'] as int? ?? 0,
      durationUs: j['durationUs'] as int,
      volume: (j['volume'] as num? ?? 1).toDouble(),
      fadeInUs: j['fadeInUs'] as int? ?? 0,
      fadeOutUs: j['fadeOutUs'] as int? ?? 0,
      enabled: j['enabled'] as bool? ?? true,
      track: j['track'] as int? ?? 0,
      group: j['group'] as String? ?? 'sfx',
    );
    clip.validate();
    return clip;
  }
}
