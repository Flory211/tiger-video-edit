import 'dart:convert';
import 'dart:io';

import 'model.dart';
import 'effect_recipes.dart';

const autoEditProfiles = [
  'Smooth',
  'Aggressive',
  'Phonk',
  'Anime',
  'Cinematic',
  'Glitch',
];

class EditTemplate {
  final String id, name, profile;
  final bool portrait;
  final int beatStep;
  final List<EffectInstance> effects;
  final List<AnimationTrack> animations;
  final List<GlobalAdjustmentLayer> globalEffects;
  const EditTemplate({
    required this.id,
    required this.name,
    this.profile = 'Smooth',
    this.portrait = false,
    this.beatStep = 1,
    this.effects = const [],
    this.animations = const [],
    this.globalEffects = const [],
  });
  void validate() {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,100}$').hasMatch(id) ||
        name.trim().isEmpty ||
        name.length > 120 ||
        !autoEditProfiles.contains(profile) ||
        beatStep < 1 ||
        beatStep > 8 ||
        effects.length > 64 ||
        animations.length > 32 ||
        globalEffects.length > 32) {
      throw const FormatException('Некорректный шаблон');
    }
    for (final e in effects) {
      e.validate();
    }
    for (final a in animations) {
      a.validate();
    }
    for (final g in globalEffects) {
      g.validate();
    }
  }

  EditTemplate copy({String? id, String? name}) => EditTemplate(
    id: id ?? this.id,
    name: name ?? this.name,
    profile: profile,
    portrait: portrait,
    beatStep: beatStep,
    effects: effects,
    animations: animations,
    globalEffects: globalEffects,
  );
  Map<String, dynamic> toJson() => {
    'format': 'tiger-edit-template',
    'version': 1,
    'id': id,
    'name': name,
    'profile': profile,
    'portrait': portrait,
    'beatStep': beatStep,
    'effects': effects.map((e) => e.toJson()).toList(),
    'animations': animations.map((a) => a.toJson()).toList(),
    'globalEffects': globalEffects.map((g) => g.toJson()).toList(),
  };
  factory EditTemplate.fromJson(Map<String, dynamic> j) {
    if (j['format'] != 'tiger-edit-template' || j['version'] != 1) {
      throw const FormatException('Неизвестный формат шаблона');
    }
    final t = EditTemplate(
      id: j['id'] as String,
      name: j['name'] as String,
      profile: j['profile'] as String? ?? 'Smooth',
      portrait: j['portrait'] as bool? ?? false,
      beatStep: j['beatStep'] as int? ?? 1,
      effects: ((j['effects'] as List?) ?? [])
          .map((e) => EffectInstance.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      animations: ((j['animations'] as List?) ?? [])
          .map((e) => AnimationTrack.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      globalEffects: ((j['globalEffects'] as List?) ?? [])
          .map(
            (e) => GlobalAdjustmentLayer.fromJson(Map<String, dynamic>.from(e)),
          )
          .toList(),
    );
    t.validate();
    return t;
  }
}

List<EditTemplate> get builtinEditTemplates {
  const recipeNames = [
    'Smooth Camera Movement',
    'Dynamic Shake',
    'Flash Pulse',
    'Elastic Zoom',
    'Cinematic Pan',
    'Digital Glitch',
  ];
  return [
    for (var i = 0; i < autoEditProfiles.length; i++)
      EditTemplate(
        id: 'builtin_${autoEditProfiles[i].toLowerCase()}',
        name: autoEditProfiles[i],
        profile: autoEditProfiles[i],
        beatStep: i == 0 || i == 4 ? 2 : 1,
        effects: effectRecipes
            .firstWhere((r) => r.name == recipeNames[i])
            .effects,
      ),
  ];
}

class TemplateStore {
  final Directory root;
  TemplateStore(this.root);
  Future<List<EditTemplate>> load() async {
    if (!await root.exists()) return [];
    final result = <EditTemplate>[];
    await for (final f in root.list(followLinks: false)) {
      if (f is! File || !f.path.endsWith('.json')) continue;
      try {
        result.add(await read(f));
      } on FormatException {
        /* Leave corrupt originals recoverable. */
      }
    }
    return result;
  }

  Future<EditTemplate> read(File file) async {
    if (await file.length() > 512 * 1024) {
      throw const FormatException('Шаблон слишком большой');
    }
    try {
      return EditTemplate.fromJson(
        jsonDecode(await file.readAsString()) as Map<String, dynamic>,
      );
    } catch (e) {
      throw FormatException('Не удалось прочитать шаблон: $e');
    }
  }

  Future<void> save(EditTemplate template) async {
    template.validate();
    await root.create(recursive: true);
    final pending = File('${root.path}/${template.id}.json.tmp');
    await pending.writeAsString(
      const JsonEncoder.withIndent('  ').convert(template.toJson()),
      flush: true,
    );
    final dest = File('${root.path}/${template.id}.json');
    if (await dest.exists()) await dest.copy('${dest.path}.bak');
    if (await dest.exists()) await dest.delete();
    await pending.rename(dest.path);
  }

  Future<void> delete(EditTemplate t) async {
    t.validate();
    final file = File('${root.path}/${t.id}.json');
    if (await file.exists()) await file.delete();
  }
}
