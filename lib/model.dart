import 'dart:math' as math;

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
  final int effectDurationUs, sourceStartUs, durationUs;
  const Still({
    required this.path,
    this.scale = 1,
    this.x = 0,
    this.y = 0,
    this.cover = true,
    this.effects = const {},
    this.effectDurationUs = 500000,
    this.sourceStartUs = 0,
    this.durationUs = 0,
  });
  String get kind {
    final ext = path.toLowerCase().split('.').last;
    if (ext == 'gif') return 'gif';
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
    effectDurationUs: (j['effectDurationUs'] as int?) ?? 500000,
    sourceStartUs: (j['sourceStartUs'] as int?) ?? 0,
    durationUs: (j['durationUs'] as int?) ?? 0,
  );
}

class Segment {
  final int imageIndex, startFrame, frameCount;
  const Segment(this.imageIndex, this.startFrame, this.frameCount);
}

class Project {
  final String name;
  final String? audio;
  final int durationUs, startUs, endUs;
  final bool portrait;
  final List<Still> images;
  final List<Marker> markers;
  final List<Caption> captions;
  Project({
    this.name = 'Новый проект',
    this.audio,
    this.durationUs = 0,
    this.startUs = 0,
    this.endUs = 0,
    this.portrait = false,
    List<Still> images = const [],
    List<Marker> markers = const [],
    List<Caption> captions = const [],
  }) : images = List.unmodifiable(images),
       markers = List.unmodifiable(markers),
       captions = List.unmodifiable(captions);
  int get width => portrait ? 1080 : 1920;
  int get height => portrait ? 1920 : 1080;
  int get totalFrames => ((endUs - startUs) * fps + 999999) ~/ 1000000;
  Project copy({
    String? name,
    String? audio,
    int? durationUs,
    int? startUs,
    int? endUs,
    bool? portrait,
    List<Still>? images,
    List<Marker>? markers,
    List<Caption>? captions,
  }) => Project(
    name: name ?? this.name,
    audio: audio ?? this.audio,
    durationUs: durationUs ?? this.durationUs,
    startUs: startUs ?? this.startUs,
    endUs: endUs ?? this.endUs,
    portrait: portrait ?? this.portrait,
    images: images ?? this.images,
    markers: markers ?? this.markers,
    captions: captions ?? this.captions,
  );
  bool get needsFrameRendering =>
      captions.isNotEmpty ||
      images.any(
        (s) => s.kind != 'image' || s.effects.values.any((v) => v > 0),
      );
  Segment? segmentAt(int sourceUs) {
    final frame = math.max(0, (sourceUs - startUs) * fps ~/ 1000000);
    Segment? found;
    for (final s in segments) {
      if (s.startFrame > frame) break;
      found = s;
    }
    return found;
  }

  List<Segment> get segments {
    if (images.isEmpty || totalFrames <= 0) return [];
    final times =
        markers
            .where((m) => m.timeUs > startUs && m.timeUs < endUs)
            .map((m) => m.timeUs)
            .toSet()
            .toList()
          ..sort();
    final cuts = <int, int>{0: 0};
    for (var i = 0; i < times.length; i++) {
      final frame = ((times[i] - startUs) * fps + 999999) ~/ 1000000;
      if (frame < totalFrames) cuts[frame] = (i + 1) % images.length;
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
    if (schedule.isEmpty) return -1;
    final frame = math.max(0, (sourceUs - startUs) * fps ~/ 1000000);
    var index = 0;
    for (final segment in schedule) {
      if (segment.startFrame > frame) break;
      index = segment.imageIndex;
    }
    return index;
  }

  void validate() {
    if (name.length > 300 ||
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
    for (final s in images) {
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
    'version': 2,
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
      if (j['version'] != 1 && j['version'] != 2) {
        throw const FormatException('Неподдерживаемая версия проекта');
      }
      final p = Project(
        name: j['name'] as String,
        audio: j['audio'] as String?,
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
    if (_undo.length > 100) _undo.removeAt(0);
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
