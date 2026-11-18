import 'dart:math' as math;

import 'effects.dart';
import 'audio_clip.dart';
export 'audio_clip.dart';
export 'effects.dart';

const fps = 30;
const effectNames = ['shake', 'zoom', 'blur', 'glow', 'flash', 'rgb', 'glitch'];

class EffectPreset {
  final String name;
  final Map<String, double> effects;
  final int durationUs;
  const EffectPreset({
    required this.name,
    required this.effects,
    this.durationUs = 500000,
  });
  Map<String, dynamic> toJson() => {
    'name': name,
    'effects': effects,
    'durationUs': durationUs,
  };
  factory EffectPreset.fromJson(Map<String, dynamic> j) => EffectPreset(
    name: j['name'] as String,
    effects: (j['effects'] as Map).map(
      (k, v) => MapEntry(k as String, (v as num).toDouble()),
    ),
    durationUs: j['durationUs'] as int,
  );
}

const builtinEffectPresets = <String, EffectPreset>{
  'Без эффектов': EffectPreset(name: 'Без эффектов', effects: {}),
  'Удар': EffectPreset(
    name: 'Удар',
    effects: {'shake': .45, 'zoom': .5, 'flash': .35},
    durationUs: 350000,
  ),
  'Мягкий': EffectPreset(
    name: 'Мягкий',
    effects: {'zoom': .3, 'glow': .4, 'blur': .15},
    durationUs: 1000000,
  ),
  'Glitch': EffectPreset(
    name: 'Glitch',
    effects: {'rgb': .6, 'glitch': .5, 'shake': .15},
    durationUs: 500000,
  ),
};

class Caption {
  final String id, text;
  final int startUs, endUs, color;
  final double x, y, fontSize;
  const Caption({
    required this.id,
    required this.text,
    required this.startUs,
    required this.endUs,
    this.x = .5,
    this.y = .85,
    this.fontSize = 64,
    this.color = 0xffffffff,
  });
  Caption copy({
    String? text,
    int? startUs,
    int? endUs,
    double? x,
    double? y,
    double? fontSize,
    int? color,
  }) => Caption(
    id: id,
    text: text ?? this.text,
    startUs: startUs ?? this.startUs,
    endUs: endUs ?? this.endUs,
    x: x ?? this.x,
    y: y ?? this.y,
    fontSize: fontSize ?? this.fontSize,
    color: color ?? this.color,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'startUs': startUs,
    'endUs': endUs,
    'x': x,
    'y': y,
    'fontSize': fontSize,
    'color': color,
  };
  factory Caption.fromJson(Map<String, dynamic> j) => Caption(
    id: j['id'] as String,
    text: j['text'] as String,
    startUs: j['startUs'] as int,
    endUs: j['endUs'] as int,
    x: (j['x'] as num).toDouble(),
    y: (j['y'] as num).toDouble(),
    fontSize: (j['fontSize'] as num).toDouble(),
    color: j['color'] as int,
  );
}

class Marker {
  final String id;
  final int timeUs;
  const Marker({required this.id, required this.timeUs});
  Map<String, dynamic> toJson() => {'id': id, 'timeUs': timeUs};
  factory Marker.fromJson(Map<String, dynamic> j) =>
      Marker(id: j['id'] as String, timeUs: j['timeUs'] as int);
}

class Still {
  final String path;
  final double scale, x, y;
  final bool cover;
  final Map<String, double> effects;
  final List<EffectInstance> effectStack;
  final List<AnimationTrack> animations;
  final int effectDurationUs, sourceStartUs, durationUs;
  const Still({
    required this.path,
    this.scale = 1,
    this.x = 0,
    this.y = 0,
    this.cover = true,
    this.effects = const {},
    this.effectStack = const [],
    this.animations = const [],
    this.effectDurationUs = 500000,
    this.sourceStartUs = 0,
    this.durationUs = 0,
  });
  String get kind {
    final ext = path.toLowerCase().split('.').last;
    if (ext == 'gif') {
      return 'gif';
    }
    return ['mp4', 'mov', 'mkv', 'webm', 'm4v'].contains(ext)
        ? 'video'
        : 'image';
  }

  Still copy({
    String? path,
    double? scale,
    double? x,
    double? y,
    bool? cover,
    Map<String, double>? effects,
    List<EffectInstance>? effectStack,
    List<AnimationTrack>? animations,
    int? effectDurationUs,
    int? sourceStartUs,
    int? durationUs,
  }) => Still(
    path: path ?? this.path,
    scale: scale ?? this.scale,
    x: x ?? this.x,
    y: y ?? this.y,
    cover: cover ?? this.cover,
    effects: effects ?? this.effects,
    effectStack: effectStack ?? this.effectStack,
    animations: animations ?? this.animations,
    effectDurationUs: effectDurationUs ?? this.effectDurationUs,
    sourceStartUs: sourceStartUs ?? this.sourceStartUs,
    durationUs: durationUs ?? this.durationUs,
  );
  Map<String, dynamic> toJson() => {
    'path': path,
    'scale': scale,
    'x': x,
    'y': y,
    'cover': cover,
    'effects': effects,
    'effectStack': effectStack.map((e) => e.toJson()).toList(),
    'animations': animations.map((e) => e.toJson()).toList(),
    'effectDurationUs': effectDurationUs,
    'sourceStartUs': sourceStartUs,
    'durationUs': durationUs,
  };
  factory Still.fromJson(Map<String, dynamic> j) => Still(
    path: j['path'] as String,
    scale: (j['scale'] as num).toDouble(),
    x: (j['x'] as num).toDouble(),
    y: (j['y'] as num).toDouble(),
    cover: j['cover'] as bool,
    effects: ((j['effects'] as Map?) ?? {}).map(
      (k, v) => MapEntry(k as String, (v as num).toDouble()),
    ),
    effectStack: ((j['effectStack'] as List?) ?? [])
        .map((e) => EffectInstance.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
    animations: ((j['animations'] as List?) ?? [])
        .map((e) => AnimationTrack.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
    effectDurationUs: (j['effectDurationUs'] as int?) ?? 500000,
    sourceStartUs: (j['sourceStartUs'] as int?) ?? 0,
    durationUs: (j['durationUs'] as int?) ?? 0,
  );
}

class Segment {
  final int imageIndex, startFrame, frameCount;
  const Segment(this.imageIndex, this.startFrame, this.frameCount);
}

class VisualClip {
  final String id;
  final Still media;
  final int startUs, durationUs, track;
  final double opacity;
  final bool enabled;
  const VisualClip({
    required this.id,
    required this.media,
    required this.startUs,
    required this.durationUs,
    this.track = 1,
    this.opacity = 1,
    this.enabled = true,
  });
  int get endUs => startUs + durationUs;
  bool activeAt(int timeUs) => enabled && timeUs >= startUs && timeUs < endUs;
  VisualClip copy({
    Still? media,
    int? startUs,
    int? durationUs,
    int? track,
    double? opacity,
    bool? enabled,
  }) => VisualClip(
    id: id,
    media: media ?? this.media,
    startUs: startUs ?? this.startUs,
    durationUs: durationUs ?? this.durationUs,
    track: track ?? this.track,
    opacity: opacity ?? this.opacity,
    enabled: enabled ?? this.enabled,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'media': media.toJson(),
    'startUs': startUs,
    'durationUs': durationUs,
    'track': track,
    'opacity': opacity,
    'enabled': enabled,
  };
  factory VisualClip.fromJson(Map<String, dynamic> j) => VisualClip(
    id: j['id'] as String,
    media: Still.fromJson(Map<String, dynamic>.from(j['media'] as Map)),
    startUs: j['startUs'] as int,
    durationUs: j['durationUs'] as int,
    track: j['track'] as int? ?? 1,
    opacity: (j['opacity'] as num? ?? 1).toDouble(),
    enabled: j['enabled'] as bool? ?? true,
  );
}

class Project {
  Set<String> get mediaReferences => {
    ?audio,
    ...images.map((s) => s.path),
    ...audioClips.map((c) => c.path),
    ...visualClips.map((c) => c.media.path),
  };
  final String name;
  final String? audio;
  final String musicCredit;
  final int durationUs, startUs, endUs;
  final bool portrait;
  final List<Still> images;
  final List<Marker> markers;
  final List<Caption> captions;
  final List<GlobalAdjustmentLayer> globalEffects;
  final bool globalEffectsEnabled;
  final List<AudioClip> audioClips;
  final double musicVolume, soundVolume;
  final List<VisualClip> visualClips;
  final int frameRate, resolution, videoCrf;
  Project({
    this.name = 'Новый проект',
    this.audio,
    this.musicCredit = '',
    this.durationUs = 0,
    this.startUs = 0,
    this.endUs = 0,
    this.portrait = false,
    List<Still> images = const [],
    List<Marker> markers = const [],
    List<Caption> captions = const [],
    this.globalEffects = const [],
    this.globalEffectsEnabled = true,
    this.audioClips = const [],
    this.musicVolume = 1,
    this.soundVolume = 1,
    List<VisualClip> visualClips = const [],
    this.frameRate = 30,
    this.resolution = 1080,
    this.videoCrf = 18,
  }) : images = List.unmodifiable(images),
       markers = List.unmodifiable(markers),
       captions = List.unmodifiable(captions),
       visualClips = List.unmodifiable(visualClips);
  int get width =>
      portrait ? resolution : (resolution * 16 / 9 / 2).round() * 2;
  int get height =>
      portrait ? (resolution * 16 / 9 / 2).round() * 2 : resolution;
  int get totalFrames => ((endUs - startUs) * frameRate + 999999) ~/ 1000000;
  Project copy({
    String? name,
    String? audio,
    String? musicCredit,
    int? durationUs,
    int? startUs,
    int? endUs,
    bool? portrait,
    List<Still>? images,
    List<Marker>? markers,
    List<Caption>? captions,
    List<GlobalAdjustmentLayer>? globalEffects,
    bool? globalEffectsEnabled,
    List<AudioClip>? audioClips,
    double? musicVolume,
    double? soundVolume,
    List<VisualClip>? visualClips,
    int? frameRate,
    int? resolution,
    int? videoCrf,
  }) => Project(
    name: name ?? this.name,
    audio: audio ?? this.audio,
    musicCredit: musicCredit ?? this.musicCredit,
    durationUs: durationUs ?? this.durationUs,
    startUs: startUs ?? this.startUs,
    endUs: endUs ?? this.endUs,
    portrait: portrait ?? this.portrait,
    images: images ?? this.images,
    markers: markers ?? this.markers,
    captions: captions ?? this.captions,
    globalEffects: globalEffects ?? this.globalEffects,
    globalEffectsEnabled: globalEffectsEnabled ?? this.globalEffectsEnabled,
    audioClips: audioClips ?? this.audioClips,
    musicVolume: musicVolume ?? this.musicVolume,
    soundVolume: soundVolume ?? this.soundVolume,
    visualClips: visualClips ?? this.visualClips,
    frameRate: frameRate ?? this.frameRate,
    resolution: resolution ?? this.resolution,
    videoCrf: videoCrf ?? this.videoCrf,
  );
  bool get needsFrameRendering =>
      visualClips.any((c) => c.enabled) ||
      captions.isNotEmpty ||
      (globalEffectsEnabled &&
          globalEffects.any(
            (l) => l.enabled && l.effects.any((e) => e.enabled),
          )) ||
      images.any(
        (s) =>
            s.kind != 'image' ||
            s.effectStack.any((e) => e.enabled) ||
            s.animations.any((e) => e.enabled) ||
            s.effects.values.any((v) => v > 0),
      );
  Segment? segmentAt(int sourceUs) {
    final frame = math.max(0, (sourceUs - startUs) * frameRate ~/ 1000000);
    Segment? found;
    for (final s in segments) {
      if (s.startFrame > frame) {
        break;
      }
      found = s;
    }
    return found;
  }

  List<Segment> get segments {
    if (images.isEmpty || totalFrames <= 0) {
      return [];
    }
    final times =
        markers
            .where((m) => m.timeUs > startUs && m.timeUs < endUs)
            .map((m) => m.timeUs)
            .toSet()
            .toList()
          ..sort();
    final cuts = <int, int>{0: 0};
    for (var i = 0; i < times.length; i++) {
      final frame = ((times[i] - startUs) * frameRate + 999999) ~/ 1000000;
      if (frame < totalFrames) {
        cuts[frame] = (i + 1) % images.length;
      }
    }
    final frames = cuts.keys.toList()..sort();
    return [
      for (var i = 0; i < frames.length; i++)
        Segment(
          cuts[frames[i]]!,
          frames[i],
          (i + 1 < frames.length ? frames[i + 1] : totalFrames) - frames[i],
        ),
    ];
  }

  int imageIndexAt(int sourceUs) {
    final schedule = segments;
    if (schedule.isEmpty) {
      return -1;
    }
    final frame = math.max(0, (sourceUs - startUs) * frameRate ~/ 1000000);
    var index = 0;
    for (final segment in schedule) {
      if (segment.startFrame > frame) {
        break;
      }
      index = segment.imageIndex;
    }
    return index;
  }

  void validate() {
    if (![24, 30, 60].contains(frameRate) ||
        ![480, 720, 1080].contains(resolution) ||
        videoCrf < 16 ||
        videoCrf > 32 ||
        visualClips.length > 1000) {
      throw const FormatException('Некорректные настройки экспорта или слои');
    }
    final visualIds = <String>{};
    void checkConcurrency(Iterable<(int, int)> spans, String label) {
      final events =
          <MapEntry<int, int>>[
            for (final s in spans) ...[MapEntry(s.$1, 1), MapEntry(s.$2, -1)],
          ]..sort(
            (a, b) => a.key == b.key
                ? a.value.compareTo(b.value)
                : a.key.compareTo(b.key),
          );
      var active = 0;
      for (final event in events) {
        active += event.value;
        if (active > 16) {
          throw FormatException('Одновременно допустимо до 16 $label');
        }
      }
    }

    checkConcurrency(
      visualClips
          .where((c) => c.enabled && c.opacity > 0)
          .map((c) => (c.startUs, c.endUs)),
      'визуальных слоёв',
    );
    checkConcurrency(
      audioClips
          .where((c) => c.enabled && c.volume > 0)
          .map((c) => (c.startUs, c.endUs)),
      'аудиоклипов',
    );
    for (final c in visualClips) {
      if (c.id.isEmpty ||
          !visualIds.add(c.id) ||
          c.startUs < 0 ||
          c.durationUs <= 0 ||
          c.durationUs > 86400000000 ||
          c.track < 1 ||
          c.track > 15 ||
          !c.opacity.isFinite ||
          c.opacity < 0 ||
          c.opacity > 1) {
        throw const FormatException('Некорректный визуальный слой');
      }
      Project(images: [c.media]).validate();
    }
    if (audioClips.length > 1024 ||
        [musicVolume, soundVolume].any((v) => !v.isFinite || v < 0 || v > 2)) {
      throw const FormatException("Invalid audio levels");
    }
    final audioIds = <String>{};
    for (final clip in audioClips) {
      clip.validate();
      if (!audioIds.add(clip.id)) {
        throw const FormatException("Duplicate audio ID");
      }
    }
    if (name.length > 300 ||
        musicCredit.length > 8192 ||
        durationUs < 0 ||
        startUs < 0 ||
        endUs > durationUs ||
        (audio != null && endUs <= startUs) ||
        markers.length > 100000 ||
        images.length > 10000) {
      throw const FormatException('Некорректный проект или границы отрывка');
    }
    final ids = <String>{};
    for (final m in markers) {
      if (m.timeUs < 0 || m.timeUs > durationUs || !ids.add(m.id)) {
        throw const FormatException('Некорректные маркеры');
      }
    }
    final layerIds = <String>{};
    for (final l in globalEffects) {
      l.validate();
      if (!layerIds.add(l.id) ||
          l.endUs > durationUs ||
          l.markerIds.any((id) => !ids.contains(id))) {
        throw const FormatException("Invalid global layer references");
      }
    }
    for (final s in images) {
      validateEffects(s.effectStack);
      final animationIds = <String>{};
      for (final a in s.animations) {
        a.validate();
        if (!animationIds.add(a.id)) {
          throw const FormatException("Duplicate animation ID");
        }
      }
      if (s.sourceStartUs < 0 ||
          s.durationUs < 0 ||
          (s.durationUs > 0 && s.sourceStartUs >= s.durationUs) ||
          s.effectDurationUs < 1000 ||
          s.effectDurationUs > 10000000 ||
          s.effects.entries.any(
            (e) =>
                !effectNames.contains(e.key) ||
                !e.value.isFinite ||
                e.value < 0 ||
                e.value > 1,
          )) {
        throw const FormatException(
          'Некорректные эффекты или начало фрагмента',
        );
      }
      if (s.path.isEmpty ||
          !s.scale.isFinite ||
          s.scale < 0.1 ||
          s.scale > 8 ||
          !s.x.isFinite ||
          !s.y.isFinite ||
          s.x.abs() > 2 ||
          s.y.abs() > 2) {
        throw const FormatException('Некорректные параметры изображения');
      }
    }
    final captionIds = <String>{};
    if (captions.length > 1000) {
      throw const FormatException('Слишком много надписей');
    }
    for (final c in captions) {
      if (!captionIds.add(c.id) ||
          c.text.trim().isEmpty ||
          c.text.length > 2000 ||
          c.startUs < 0 ||
          c.endUs <= c.startUs ||
          c.endUs > durationUs ||
          !c.x.isFinite ||
          !c.y.isFinite ||
          c.x < 0 ||
          c.x > 1 ||
          c.y < 0 ||
          c.y > 1 ||
          !c.fontSize.isFinite ||
          c.fontSize < 8 ||
          c.fontSize > 300 ||
          c.color < 0 ||
          c.color > 0xffffffff) {
        throw const FormatException('Некорректная надпись или её время');
      }
    }
  }

  Map<String, dynamic> toJson() => {
    'version': 3,
    'musicCredit': musicCredit,
    'globalEffectsEnabled': globalEffectsEnabled,
    'audioClips': audioClips.map((c) => c.toJson()).toList(),
    'musicVolume': musicVolume,
    'soundVolume': soundVolume,
    'visualClips': visualClips.map((c) => c.toJson()).toList(),
    'frameRate': frameRate,
    'resolution': resolution,
    'videoCrf': videoCrf,
    'globalEffects': globalEffects.map((e) => e.toJson()).toList(),
    'name': name,
    'audio': audio,
    'durationUs': durationUs,
    'startUs': startUs,
    'endUs': endUs,
    'portrait': portrait,
    'images': images.map((s) => s.toJson()).toList(),
    'markers': markers.map((m) => m.toJson()).toList(),
    'captions': captions.map((c) => c.toJson()).toList(),
  };
  factory Project.fromJson(Map<String, dynamic> j) {
    try {
      if (j['version'] != 1 && j['version'] != 2 && j['version'] != 3) {
        throw const FormatException('Неподдерживаемая версия проекта');
      }
      final p = Project(
        globalEffectsEnabled: j['globalEffectsEnabled'] as bool? ?? true,
        audioClips: ((j['audioClips'] as List?) ?? [])
            .map((e) => AudioClip.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        musicVolume: (j['musicVolume'] as num? ?? 1).toDouble(),
        soundVolume: (j['soundVolume'] as num? ?? 1).toDouble(),
        visualClips: ((j['visualClips'] as List?) ?? [])
            .map((v) => VisualClip.fromJson(Map<String, dynamic>.from(v)))
            .toList(),
        frameRate: j['frameRate'] as int? ?? 30,
        resolution: j['resolution'] as int? ?? 1080,
        videoCrf: j['videoCrf'] as int? ?? 18,
        globalEffects: ((j['globalEffects'] as List?) ?? [])
            .map(
              (e) =>
                  GlobalAdjustmentLayer.fromJson(Map<String, dynamic>.from(e)),
            )
            .toList(),
        name: j['name'] as String,
        audio: j['audio'] as String?,
        musicCredit: j['musicCredit'] as String? ?? '',
        durationUs: j['durationUs'] as int,
        startUs: j['startUs'] as int,
        endUs: j['endUs'] as int,
        portrait: j['portrait'] as bool,
        images: (j['images'] as List)
            .map((e) => Still.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        markers: (j['markers'] as List)
            .map((e) => Marker.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        captions: ((j['captions'] as List?) ?? [])
            .map((e) => Caption.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
      p.validate();
      return p;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Повреждённый файл проекта');
    }
  }
}

class ProjectHistory {
  Project current;
  final List<Project> _undo = [], _redo = [];
  ProjectHistory(this.current);
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  void change(Project next) {
    _undo.add(current);
    if (_undo.length > 100) {
      _undo.removeAt(0);
    }
    _redo.clear();
    current = next;
  }

  void undo() {
    if (canUndo) {
      _redo.add(current);
      current = _undo.removeLast();
    }
  }

  void redo() {
    if (canRedo) {
      _undo.add(current);
      current = _redo.removeLast();
    }
  }
}
