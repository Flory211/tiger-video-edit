import 'dart:math' as math;

import 'package:flutter/animation.dart' show Curves, Cubic;

enum Interpolation {
  linear,
  easeIn,
  easeOut,
  easeInOut,
  cubicBezier,
  back,
  bounce,
  elastic,
}

enum AnimationProperty { x, y, scale, rotation, opacity }

enum GlobalEffectMode {
  always,
  range,
  everyMarker,
  selectedMarkers,
  imageChanges,
}

const effectCategories = <String, List<String>>{
  'Motion': ['shake', 'zoom', 'pan', 'rotation', 'pulse'],
  'Glitch': ['glitch', 'rgb', 'scanlines'],
  'Light': ['blur', 'glow', 'flash', 'vignette', 'lightSweep'],
  'Transitions': ['crossfade', 'slide', 'wipe'],
};
final supportedEffectTypes = effectCategories.values.expand((v) => v).toSet();

double interpolateCurve(double t, Interpolation curve, List<double> bezier) {
  t = t.clamp(0.0, 1.0);
  if (t == 0 || t == 1) {
    return t;
  }
  return switch (curve) {
    Interpolation.linear => t,
    Interpolation.easeIn => Curves.easeIn.transform(t),
    Interpolation.easeOut => Curves.easeOut.transform(t),
    Interpolation.easeInOut => Curves.easeInOut.transform(t),
    Interpolation.cubicBezier => Cubic(
      bezier[0],
      bezier[1],
      bezier[2],
      bezier[3],
    ).transform(t),
    Interpolation.back => Curves.easeOutBack.transform(t),
    Interpolation.bounce => Curves.bounceOut.transform(t),
    Interpolation.elastic => Curves.elasticOut.transform(t),
  };
}

void validateCurve(List<double> b) {
  if (b.length != 4 ||
      b.any((v) => !v.isFinite || v.abs() > 10) ||
      b[0] < 0 ||
      b[0] > 1 ||
      b[2] < 0 ||
      b[2] > 1) {
    throw const FormatException('Invalid Bezier curve');
  }
}

class Keyframe {
  final int timeUs;
  final double value;
  final Interpolation interpolation;
  final List<double> bezier;
  const Keyframe({
    required this.timeUs,
    required this.value,
    this.interpolation = Interpolation.linear,
    this.bezier = const [.25, .1, .25, 1],
  });
  Map<String, dynamic> toJson() => {
    'timeUs': timeUs,
    'value': value,
    'interpolation': interpolation.name,
    'bezier': bezier,
  };
  factory Keyframe.fromJson(Map<String, dynamic> j) => Keyframe(
    timeUs: j['timeUs'] as int,
    value: (j['value'] as num).toDouble(),
    interpolation: Interpolation.values.byName(
      j['interpolation'] as String? ?? 'linear',
    ),
    bezier: ((j['bezier'] as List?) ?? [.25, .1, .25, 1])
        .map((v) => (v as num).toDouble())
        .toList(),
  );
}

class AnimationTrack {
  final String id;
  final AnimationProperty property;
  final List<Keyframe> keyframes;
  final bool enabled;
  const AnimationTrack({
    required this.id,
    required this.property,
    required this.keyframes,
    this.enabled = true,
  });
  double evaluate(int timeUs) {
    if (keyframes.isEmpty) {
      return 0;
    }
    if (timeUs <= keyframes.first.timeUs) {
      return keyframes.first.value;
    }
    for (var i = 1; i < keyframes.length; i++) {
      final a = keyframes[i - 1], b = keyframes[i];
      if (timeUs <= b.timeUs) {
        return a.value +
            (b.value - a.value) *
                interpolateCurve(
                  (timeUs - a.timeUs) / (b.timeUs - a.timeUs),
                  a.interpolation,
                  a.bezier,
                );
      }
    }
    return keyframes.last.value;
  }

  void validate() {
    if (id.isEmpty || keyframes.isEmpty || keyframes.length > 10000) {
      throw const FormatException('Invalid animation');
    }
    var previous = -1;
    for (final k in keyframes) {
      if (k.timeUs <= previous || !k.value.isFinite || k.value.abs() > 10000) {
        throw const FormatException('Invalid keyframe');
      }
      validateCurve(k.bezier);
      previous = k.timeUs;
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'property': property.name,
    'enabled': enabled,
    'keyframes': keyframes.map((k) => k.toJson()).toList(),
  };
  factory AnimationTrack.fromJson(Map<String, dynamic> j) => AnimationTrack(
    id: j['id'] as String,
    property: AnimationProperty.values.byName(j['property'] as String),
    enabled: j['enabled'] as bool? ?? true,
    keyframes: (j['keyframes'] as List)
        .map((k) => Keyframe.fromJson(Map<String, dynamic>.from(k)))
        .toList(),
  );
}

class EffectInstance {
  final String id, type;
  final bool enabled;
  final double strength, frequency, beginIntensity, endIntensity, smoothing;
  final int durationUs, delayUs;
  final Interpolation curve;
  final List<double> bezier;
  const EffectInstance({
    required this.id,
    required this.type,
    this.enabled = true,
    this.strength = .5,
    this.frequency = 0,
    this.beginIntensity = 1,
    this.endIntensity = 0,
    this.smoothing = 0,
    this.durationUs = 500000,
    this.delayUs = 0,
    this.curve = Interpolation.linear,
    this.bezier = const [.25, .1, .25, 1],
  });
  EffectInstance copy({
    String? id,
    String? type,
    bool? enabled,
    double? strength,
    double? frequency,
    double? beginIntensity,
    double? endIntensity,
    double? smoothing,
    int? durationUs,
    int? delayUs,
    Interpolation? curve,
    List<double>? bezier,
  }) => EffectInstance(
    id: id ?? this.id,
    type: type ?? this.type,
    enabled: enabled ?? this.enabled,
    strength: strength ?? this.strength,
    frequency: frequency ?? this.frequency,
    beginIntensity: beginIntensity ?? this.beginIntensity,
    endIntensity: endIntensity ?? this.endIntensity,
    smoothing: smoothing ?? this.smoothing,
    durationUs: durationUs ?? this.durationUs,
    delayUs: delayUs ?? this.delayUs,
    curve: curve ?? this.curve,
    bezier: bezier ?? this.bezier,
  );
  double amountAt(int localUs, {bool holdLast = false}) {
    final elapsed = localUs - delayUs;
    if (!enabled || elapsed < 0 || (!holdLast && elapsed >= durationUs)) {
      return 0;
    }
    var t = interpolateCurve(
      (elapsed / durationUs).clamp(0.0, 1.0),
      curve,
      bezier,
    );
    t = t * (1 - smoothing) + (t * t * (3 - 2 * t)) * smoothing;
    final pulse = frequency == 0
        ? 1.0
        : (.5 + .5 * math.cos(elapsed / 1000000 * frequency * 2 * math.pi));
    return strength *
        (beginIntensity + (endIntensity - beginIntensity) * t) *
        pulse;
  }

  void validate() {
    if (id.isEmpty ||
        !supportedEffectTypes.contains(type) ||
        durationUs < 1000 ||
        durationUs > 3600000000 ||
        delayUs < 0 ||
        delayUs > 3600000000 ||
        !frequency.isFinite ||
        frequency < 0 ||
        frequency > 60 ||
        [
          strength,
          beginIntensity,
          endIntensity,
          smoothing,
        ].any((v) => !v.isFinite || v < 0 || v > 1)) {
      throw const FormatException('Invalid effect');
    }
    validateCurve(bezier);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'enabled': enabled,
    'strength': strength,
    'frequency': frequency,
    'beginIntensity': beginIntensity,
    'endIntensity': endIntensity,
    'smoothing': smoothing,
    'durationUs': durationUs,
    'delayUs': delayUs,
    'curve': curve.name,
    'bezier': bezier,
  };
  factory EffectInstance.fromJson(Map<String, dynamic> j) => EffectInstance(
    id: j['id'] as String,
    type: j['type'] as String,
    enabled: j['enabled'] as bool? ?? true,
    strength: (j['strength'] as num? ?? .5).toDouble(),
    frequency: (j['frequency'] as num? ?? 0).toDouble(),
    beginIntensity: (j['beginIntensity'] as num? ?? 1).toDouble(),
    endIntensity: (j['endIntensity'] as num? ?? 0).toDouble(),
    smoothing: (j['smoothing'] as num? ?? 0).toDouble(),
    durationUs: j['durationUs'] as int? ?? 500000,
    delayUs: j['delayUs'] as int? ?? 0,
    curve: Interpolation.values.byName(j['curve'] as String? ?? 'linear'),
    bezier: ((j['bezier'] as List?) ?? [.25, .1, .25, 1])
        .map((v) => (v as num).toDouble())
        .toList(),
  );
}

class GlobalAdjustmentLayer {
  final String id;
  final bool enabled;
  final GlobalEffectMode mode;
  final int startUs, endUs;
  final List<String> markerIds;
  final List<EffectInstance> effects;
  const GlobalAdjustmentLayer({
    required this.id,
    this.enabled = true,
    this.mode = GlobalEffectMode.always,
    this.startUs = 0,
    this.endUs = 0,
    this.markerIds = const [],
    this.effects = const [],
  });
  GlobalAdjustmentLayer copy({
    bool? enabled,
    GlobalEffectMode? mode,
    int? startUs,
    int? endUs,
    List<String>? markerIds,
    List<EffectInstance>? effects,
  }) => GlobalAdjustmentLayer(
    id: id,
    enabled: enabled ?? this.enabled,
    mode: mode ?? this.mode,
    startUs: startUs ?? this.startUs,
    endUs: endUs ?? this.endUs,
    markerIds: markerIds ?? this.markerIds,
    effects: effects ?? this.effects,
  );
  int? localTime(
    int sourceUs, {
    required int projectStartUs,
    required Iterable<MapEntry<String, int>> markers,
    required Iterable<int> imageChanges,
  }) {
    if (!enabled || sourceUs < projectStartUs) {
      return null;
    }
    if (mode == GlobalEffectMode.always) {
      return sourceUs - projectStartUs;
    }
    if (mode == GlobalEffectMode.range) {
      return sourceUs >= startUs && sourceUs < endUs
          ? sourceUs - startUs
          : null;
    }
    final triggers = mode == GlobalEffectMode.imageChanges
        ? imageChanges
        : markers
              .where(
                (m) =>
                    mode == GlobalEffectMode.everyMarker ||
                    markerIds.contains(m.key),
              )
              .map((m) => m.value);
    int? latest;
    for (final t in triggers) {
      if (t >= projectStartUs &&
          t <= sourceUs &&
          (latest == null || t > latest)) {
        latest = t;
      }
    }
    return latest == null ? null : sourceUs - latest;
  }

  void validate() {
    if (id.isEmpty ||
        startUs < 0 ||
        endUs < 0 ||
        (mode == GlobalEffectMode.range && endUs <= startUs) ||
        markerIds.toSet().length != markerIds.length) {
      throw const FormatException('Invalid global layer');
    }
    validateEffects(effects);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'enabled': enabled,
    'mode': mode.name,
    'startUs': startUs,
    'endUs': endUs,
    'markerIds': markerIds,
    'effects': effects.map((e) => e.toJson()).toList(),
  };
  factory GlobalAdjustmentLayer.fromJson(Map<String, dynamic> j) =>
      GlobalAdjustmentLayer(
        id: j['id'] as String,
        enabled: j['enabled'] as bool? ?? true,
        mode: GlobalEffectMode.values.byName(j['mode'] as String? ?? 'always'),
        startUs: j['startUs'] as int? ?? 0,
        endUs: j['endUs'] as int? ?? 0,
        markerIds: ((j['markerIds'] as List?) ?? []).cast<String>(),
        effects: ((j['effects'] as List?) ?? [])
            .map((e) => EffectInstance.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

void validateEffects(List<EffectInstance> effects) {
  final ids = <String>{};
  if (effects.length > 100) {
    throw const FormatException('Too many effects');
  }
  for (final e in effects) {
    e.validate();
    if (!ids.add(e.id)) {
      throw const FormatException('Duplicate effect ID');
    }
  }
}
