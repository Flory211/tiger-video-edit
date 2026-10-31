import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'editor.dart';
import 'app_settings.dart';
import 'model.dart';
import 'effect_recipes.dart';
import 'compositor.dart';

class V3Panel extends StatelessWidget {
  final Editor editor;
  const V3Panel({super.key, required this.editor});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: editor,
    builder: (context, _) {
      final p = editor.project, index = editor.selectedImage;
      final s = index >= 0 && index < p.images.length ? p.images[index] : null;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(),
          const Text(
            'СТИЛИ И ГЛОБАЛЬНЫЕ СЛОИ',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          FilledButton.tonal(
            onPressed: () => showEffectLibrary(context, editor),
            child: const Text('Библиотека стилей'),
          ),
          Wrap(
            spacing: 4,
            children: [
              TextButton(
                onPressed: editor.selectAllImages,
                child: const Text('Выделить все картинки'),
              ),
              TextButton(
                onPressed: editor.clearImageSelection,
                child: const Text('Снять выделение'),
              ),
            ],
          ),
          Text('Выбрано: ${editor.selectedImages.length}'),
          Wrap(
            spacing: 4,
            children: [
              TextButton(
                onPressed: s == null ? null : editor.copyEffects,
                child: const Text('Копировать эффекты'),
              ),
              TextButton(
                onPressed: s == null ? null : () => editor.pasteEffects(),
                child: const Text('Вставить к выбранным'),
              ),
              TextButton(
                onPressed: s == null
                    ? null
                    : () => editor.pasteEffects(all: true),
                child: const Text('Вставить ко всем'),
              ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Глобальные эффекты'),
            value: p.globalEffectsEnabled,
            onChanged: editor.setGlobalEffectsEnabled,
          ),
          for (final layer in p.globalEffects)
            Card(
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 8),
                title: Text(
                  'Слой ${layer.id}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(_modeNames[layer.mode]!),
                children: [
                  SwitchListTile(
                    title: const Text('Включён'),
                    value: layer.enabled,
                    onChanged: (v) =>
                        editor.updateGlobalLayer(layer.copy(enabled: v)),
                  ),
                  Wrap(
                    children: [
                      TextButton(
                        onPressed: () async {
                          final config = await _globalDialog(
                            context,
                            editor,
                            layer,
                          );
                          if (config != null) {
                            editor.updateGlobalLayer(
                              layer.copy(
                                mode: config.mode,
                                startUs: config.startUs,
                                endUs: config.endUs,
                                markerIds: config.markerIds,
                              ),
                            );
                          }
                        },
                        child: const Text('Режим и время'),
                      ),
                      TextButton(
                        onPressed: () => editor.deleteGlobalLayer(layer.id),
                        child: const Text('Удалить слой'),
                      ),
                    ],
                  ),
                  for (var i = 0; i < layer.effects.length; i++)
                    _effectRow(
                      context,
                      layer.effects[i],
                      (effect) => editor.updateGlobalLayer(
                        layer.copy(effects: [...layer.effects]..[i] = effect),
                      ),
                      () => editor.updateGlobalLayer(
                        layer.copy(effects: [...layer.effects]..removeAt(i)),
                      ),
                      moveUp: i == 0
                          ? null
                          : () => editor.updateGlobalLayer(
                              layer.copy(effects: _up(layer.effects, i)),
                            ),
                    ),
                ],
              ),
            ),
          if (s != null) ...[
            const Divider(),
            const Text('СТЕК ВЫБРАННОЙ КАРТИНКИ'),
            if (s.effectStack.isEmpty)
              const Text('Добавьте стиль из библиотеки'),
            for (var i = 0; i < s.effectStack.length; i++)
              _effectRow(
                context,
                s.effectStack[i],
                (effect) => editor.updateStill(
                  s.copy(effectStack: [...s.effectStack]..[i] = effect),
                ),
                () => editor.updateStill(
                  s.copy(effectStack: [...s.effectStack]..removeAt(i)),
                ),
                moveUp: i == 0
                    ? null
                    : () => editor.updateStill(
                        s.copy(effectStack: _up(s.effectStack, i)),
                      ),
              ),
            const Divider(),
            const Text('АНИМАЦИЯ И КЛЮЧИ'),
            for (final track in s.animations)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '${track.property.name}: ${track.keyframes.length} ключа',
                ),
                subtitle: CurveGraph(track: track),
                onTap: () async {
                  final a = await _animationDialog(context, track);
                  if (a != null) {
                    editor.updateStill(
                      s.copy(
                        animations: [
                          for (final t in s.animations) t.id == a.id ? a : t,
                        ],
                      ),
                    );
                  }
                },
                trailing: IconButton(
                  tooltip: 'Удалить анимацию',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => editor.updateStill(
                    s.copy(
                      animations: s.animations
                          .where((a) => a.id != track.id)
                          .toList(),
                    ),
                  ),
                ),
              ),
            TextButton(
              onPressed: () async {
                final a = await _animationDialog(context, null);
                if (a != null) {
                  editor.updateStill(s.copy(animations: [...s.animations, a]));
                }
              },
              child: const Text('Добавить анимацию'),
            ),
          ],
        ],
      );
    },
  );
}

List<T> _up<T>(List<T> source, int i) {
  final list = [...source];
  final item = list.removeAt(i);
  list.insert(i - 1, item);
  return list;
}

Widget _effectRow(
  BuildContext context,
  EffectInstance e,
  ValueChanged<EffectInstance> update,
  VoidCallback remove, {
  VoidCallback? moveUp,
}) => ListTile(
  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
  title: Text(e.type),
  subtitle: Text(
    '${(e.strength * 100).round()}% • ${e.durationUs / 1000000} с',
  ),
  leading: Checkbox(
    value: e.enabled,
    onChanged: (v) => update(e.copy(enabled: v)),
  ),
  onTap: () async {
    final next = await _effectDialog(context, e);
    if (next != null) update(next);
  },
  trailing: Wrap(
    children: [
      if (moveUp != null)
        IconButton(
          tooltip: 'Выше в стеке',
          onPressed: moveUp,
          icon: const Icon(Icons.arrow_upward, size: 18),
        ),
      IconButton(
        tooltip: 'Удалить эффект',
        onPressed: remove,
        icon: const Icon(Icons.close, size: 18),
      ),
    ],
  ),
);

Future<void> showEffectLibrary(BuildContext context, Editor editor) =>
    showDialog<void>(
      context: context,
      builder: (_) => _EffectLibrary(editor: editor),
    );

class _EffectLibrary extends StatefulWidget {
  final Editor editor;
  const _EffectLibrary({required this.editor});
  @override
  State<_EffectLibrary> createState() => _EffectLibraryState();
}

class _EffectLibraryState extends State<_EffectLibrary> {
  String search = '', category = 'Все';
  EffectRecipe? selected;
  Editor get editor => widget.editor;
  void _remember(EffectRecipe recipe) {
    _saveSettings(
      editor.settings.copyWith(
        recentEffects: [
          recipe.name,
          ...editor.settings.recentEffects.where((n) => n != recipe.name),
        ].take(20).toList(),
      ),
    );
  }

  Future<void> _saveSettings(AppSettings next) async {
    try {
      await editor.updateSettings(next);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text('Не удалось сохранить настройки: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: editor,
    builder: (context, _) {
      final recipes = effectRecipes
          .where(
            (r) =>
                r.name.toLowerCase().contains(search.toLowerCase()) &&
                (category == 'Все' ||
                    category == r.category ||
                    (category == 'Популярные' &&
                        [
                          'Dynamic Shake',
                          'Elastic Zoom',
                          'Soft Glow',
                          'Digital Glitch',
                          'Light Flash',
                        ].contains(r.name)) ||
                    (category == 'Избранные' &&
                        editor.settings.favoriteEffects.contains(r.name)) ||
                    (category == 'Недавние' &&
                        editor.settings.recentEffects.contains(r.name))),
          )
          .toList();
      return Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 760,
            maxHeight: MediaQuery.sizeOf(context).height * .9,
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Библиотека стилей',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Закрыть библиотеку',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const Text('Редактируемые комбинации Canvas-эффектов'),
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Поиск стиля',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (v) => setState(() => search = v),
                ),
                SizedBox(
                  height: 48,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final name in [
                        'Все',
                        'Популярные',
                        'Недавние',
                        'Избранные',
                        ...effectCategories.keys,
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 5),
                          child: ChoiceChip(
                            label: Text(name),
                            selected: category == name,
                            onSelected: (_) => setState(() => category = name),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    children: [
                      if (selected != null) ...[
                        SizedBox(
                          height: 132,
                          child: RecipePreview(
                            recipe: selected!,
                            editor: editor,
                          ),
                        ),
                        Text(
                          selected!.effects.map((e) => e.type).join(' + '),
                          maxLines: 2,
                        ),
                        if (selected!.needsPreviousImage)
                          const Text(
                            'Переход использует предыдущий кадр композиции',
                            style: TextStyle(fontSize: 11),
                          ),
                        Wrap(
                          spacing: 5,
                          alignment: WrapAlignment.center,
                          children: [
                            FilledButton(
                              onPressed: editor.project.images.isEmpty
                                  ? null
                                  : () {
                                      _remember(selected!);
                                      editor.applyEffectRecipe(selected!);
                                      Navigator.pop(context);
                                    },
                              child: const Text('К выбранным'),
                            ),
                            TextButton(
                              onPressed: editor.project.images.isEmpty
                                  ? null
                                  : () {
                                      _remember(selected!);
                                      editor.applyEffectRecipe(
                                        selected!,
                                        all: true,
                                      );
                                      Navigator.pop(context);
                                    },
                              child: const Text('Применить ко всем'),
                            ),
                            TextButton(
                              onPressed:
                                  editor.project.audio == null ||
                                      editor.project.endUs <=
                                          editor.project.startUs
                                  ? null
                                  : () async {
                                      final config = await _globalDialog(
                                        context,
                                        editor,
                                        null,
                                      );
                                      if (config == null || !context.mounted) {
                                        return;
                                      }
                                      _remember(selected!);
                                      editor.addGlobalEffect(
                                        selected!,
                                        mode: config.mode,
                                        startUs: config.startUs,
                                        endUs: config.endUs,
                                        markerIds: config.markerIds,
                                      );
                                      Navigator.pop(context);
                                    },
                              child: const Text('Добавить глобальный слой'),
                            ),
                          ],
                        ),
                      ],

                      if (recipes.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('Стили не найдены'),
                        ),
                      for (final r in recipes)
                        ListTile(
                          selected: selected == r,
                          title: Text(r.name),
                          subtitle: Text(r.category),
                          onTap: () => setState(() => selected = r),
                          trailing: IconButton(
                            tooltip: 'Избранное: ${r.name}',
                            icon: Icon(
                              editor.settings.favoriteEffects.contains(r.name)
                                  ? Icons.star
                                  : Icons.star_border,
                            ),
                            onPressed: () {
                              final names = {
                                ...editor.settings.favoriteEffects,
                              };
                              if (!names.add(r.name)) {
                                names.remove(r.name);
                              }
                              _saveSettings(
                                editor.settings.copyWith(
                                  favoriteEffects: names,
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class RecipePreview extends StatefulWidget {
  final EffectRecipe recipe;
  final Editor editor;
  const RecipePreview({super.key, required this.recipe, required this.editor});
  @override
  State<RecipePreview> createState() => _RecipePreviewState();
}

class _RecipePreviewState extends State<RecipePreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController clock = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  ui.Image? image, previous;
  @override
  void initState() {
    super.initState();
    _create();
  }

  Future<void> _create() async {
    Future<ui.Image> make(bool old) async {
      final r = ui.PictureRecorder();
      final canvas = Canvas(r);
      canvas.drawColor(
        old ? const Color(0xff804828) : const Color(0xff124b70),
        BlendMode.src,
      );
      for (var i = 0; i < 6; i++) {
        canvas.drawRect(
          Rect.fromLTWH(i * 45, 15 + i * 12, 28, 90),
          Paint()
            ..color = old ? const Color(0xffe8aa55) : const Color(0xff44d8ba),
        );
      }
      final p = r.endRecording();
      final img = await p.toImage(240, 140);
      p.dispose();
      return img;
    }

    final a = await make(false), b = await make(true);
    if (!mounted) {
      a.dispose();
      b.dispose();
      return;
    }
    setState(() {
      image = a;
      previous = b;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motion();
  }

  @override
  void didUpdateWidget(covariant RecipePreview old) {
    super.didUpdateWidget(old);
    _motion();
  }

  void _motion() {
    if (widget.editor.settings.animationsAllowed(
      systemReducedMotion: MediaQuery.disableAnimationsOf(context),
    )) {
      if (!clock.isAnimating) clock.repeat();
    } else {
      clock.stop();
      clock.value = .2;
    }
  }

  @override
  void dispose() {
    clock.dispose();
    image?.dispose();
    previous?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => image == null
      ? const Center(child: CircularProgressIndicator())
      : AnimatedBuilder(
          animation: clock,
          builder: (_, _) => CustomPaint(
            size: const Size(240, 140),
            painter: _RecipePainter(
              image!,
              previous!,
              widget.recipe,
              (clock.value * 1200000).round(),
            ),
          ),
        );
}

class _RecipePainter extends CustomPainter {
  final ui.Image image, previous;
  final EffectRecipe recipe;
  final int time;
  _RecipePainter(this.image, this.previous, this.recipe, this.time);
  @override
  void paint(Canvas c, Size size) {
    paintFrame(
      c,
      size,
      image,
      Still(path: 'preview', effectStack: recipe.effects),
      localUs: time,
      previousImage: previous,
      referenceWidth: 240,
    );
  }

  @override
  bool shouldRepaint(covariant _RecipePainter old) =>
      old.time != time || old.recipe != recipe;
}

const _modeNames = {
  GlobalEffectMode.always: 'Весь ролик',
  GlobalEffectMode.range: 'Отрезок времени',
  GlobalEffectMode.everyMarker: 'Каждый маркер',
  GlobalEffectMode.selectedMarkers: 'Выбранные маркеры',
  GlobalEffectMode.imageChanges: 'При смене картинки',
};

class _GlobalConfig {
  final GlobalEffectMode mode;
  final int startUs, endUs;
  final List<String> markerIds;
  _GlobalConfig(this.mode, this.startUs, this.endUs, this.markerIds);
}

Future<_GlobalConfig?> _globalDialog(
  BuildContext context,
  Editor editor,
  GlobalAdjustmentLayer? layer,
) async {
  var mode = layer?.mode ?? GlobalEffectMode.always;
  final ids = {...?layer?.markerIds};
  var start = (layer?.startUs ?? editor.project.startUs) / 1000000,
      end =
          (layer?.endUs == 0
              ? editor.project.endUs
              : layer?.endUs ?? editor.project.endUs) /
          1000000;
  final form = GlobalKey<FormState>();
  return showDialog<_GlobalConfig>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Глобальный слой'),
        scrollable: true,
        content: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<GlobalEffectMode>(
                initialValue: mode,
                isExpanded: true,
                items: [
                  for (final m in GlobalEffectMode.values)
                    DropdownMenuItem(value: m, child: Text(_modeNames[m]!)),
                ],
                onChanged: (v) => setState(() => mode = v!),
              ),
              if (mode == GlobalEffectMode.range) ...[
                _number(
                  'Начало, с',
                  start,
                  0,
                  editor.project.durationUs / 1000000,
                  (v) => start = v,
                ),
                _number(
                  'Конец, с',
                  end,
                  0,
                  editor.project.durationUs / 1000000,
                  (v) => end = v,
                  extra: () =>
                      end <= start ? 'Конец должен быть позже начала' : null,
                ),
              ],
              if (mode == GlobalEffectMode.selectedMarkers) ...[
                if (editor.project.markers.isEmpty)
                  const Text('Сначала добавьте маркеры'),
                for (final marker in editor.project.markers)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${(marker.timeUs / 1000000).toStringAsFixed(3)} с',
                    ),
                    value: ids.contains(marker.id),
                    onChanged: (v) => setState(
                      () => v! ? ids.add(marker.id) : ids.remove(marker.id),
                    ),
                  ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              if (!form.currentState!.validate()) return;
              if (mode == GlobalEffectMode.selectedMarkers && ids.isEmpty) {
                ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                  const SnackBar(content: Text('Выберите хотя бы один маркер')),
                );
                return;
              }
              Navigator.pop(
                context,
                _GlobalConfig(
                  mode,
                  (start * 1000000).round(),
                  (end * 1000000).round(),
                  ids.toList(),
                ),
              );
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    ),
  );
}

Widget _number(
  String label,
  double value,
  double min,
  double max,
  ValueChanged<double> changed, {
  String? Function()? extra,
}) => TextFormField(
  initialValue: value.toString(),
  keyboardType: const TextInputType.numberWithOptions(
    decimal: true,
    signed: true,
  ),
  decoration: InputDecoration(labelText: label),
  onChanged: (text) {
    final v = double.tryParse(text.replaceAll(',', '.'));
    if (v != null && v.isFinite && v >= min && v <= max) {
      changed(v);
    }
  },
  validator: (text) {
    final v = double.tryParse((text ?? '').replaceAll(',', '.'));
    if (v == null || !v.isFinite || v < min || v > max) {
      return 'Допустимо: $min … $max';
    }
    return extra?.call();
  },
);
Future<EffectInstance?> _effectDialog(
  BuildContext context,
  EffectInstance original,
) async {
  var e = original;
  final form = GlobalKey<FormState>();
  var bezier = [...e.bezier];
  return showDialog<EffectInstance>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text('Эффект: ${e.type}'),
        scrollable: true,
        content: SizedBox(
          width: 380,
          child: Form(
            key: form,
            onChanged: () => setState(() {}),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _number(
                  'Сила',
                  e.strength,
                  0,
                  1,
                  (v) => e = e.copy(strength: v),
                ),
                _number(
                  'Длительность, с',
                  e.durationUs / 1000000,
                  .001,
                  3600,
                  (v) => e = e.copy(durationUs: (v * 1000000).round()),
                ),
                _number(
                  'Задержка, с',
                  e.delayUs / 1000000,
                  0,
                  3600,
                  (v) => e = e.copy(delayUs: (v * 1000000).round()),
                ),
                _number(
                  'Частота, Гц',
                  e.frequency,
                  0,
                  60,
                  (v) => e = e.copy(frequency: v),
                ),
                _number(
                  'Интенсивность в начале',
                  e.beginIntensity,
                  0,
                  1,
                  (v) => e = e.copy(beginIntensity: v),
                ),
                _number(
                  'Интенсивность в конце',
                  e.endIntensity,
                  0,
                  1,
                  (v) => e = e.copy(endIntensity: v),
                ),
                _number(
                  'Сглаживание',
                  e.smoothing,
                  0,
                  1,
                  (v) => e = e.copy(smoothing: v),
                ),
                DropdownButtonFormField<Interpolation>(
                  initialValue: e.curve,
                  decoration: const InputDecoration(labelText: 'Кривая'),
                  items: [
                    for (final c in Interpolation.values)
                      DropdownMenuItem(value: c, child: Text(c.name)),
                  ],
                  onChanged: (v) => setState(() => e = e.copy(curve: v)),
                ),
                if (e.curve == Interpolation.cubicBezier)
                  for (var i = 0; i < 4; i++)
                    _number(
                      'Bezier ${['x1', 'y1', 'x2', 'y2'][i]}',
                      bezier[i],
                      i.isEven ? 0 : -10,
                      i.isEven ? 1 : 10,
                      (v) {
                        bezier[i] = v;
                        e = e.copy(bezier: [...bezier]);
                      },
                    ),
                CurveGraph(
                  track: AnimationTrack(
                    id: 'preview',
                    property: AnimationProperty.opacity,
                    keyframes: [
                      Keyframe(
                        timeUs: 0,
                        value: e.beginIntensity,
                        interpolation: e.curve,
                        bezier: e.bezier,
                      ),
                      Keyframe(timeUs: 1000000, value: e.endIntensity),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                e.validate();
                Navigator.pop(context, e);
              }
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    ),
  );
}

class CurveGraph extends StatelessWidget {
  final AnimationTrack track;
  const CurveGraph({super.key, required this.track});
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 70,
    width: 240,
    child: CustomPaint(
      painter: _CurvePainter(track, Theme.of(context).colorScheme.primary),
    ),
  );
}

class _CurvePainter extends CustomPainter {
  final AnimationTrack track;
  final Color color;
  _CurvePainter(this.track, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    if (track.keyframes.isEmpty) return;
    final duration = math.max(1, track.keyframes.last.timeUs);
    final samples = [
      for (var i = 0; i <= 100; i++) track.evaluate(duration * i ~/ 100),
    ];
    final lo = math.min(0.0, samples.reduce(math.min)),
        hi = math.max(1.0, samples.reduce(math.max));
    final path = Path();
    for (var i = 0; i < samples.length; i++) {
      final x = i / 100 * size.width,
          y =
              size.height -
              5 -
              (samples[i] - lo) / (hi - lo) * (size.height - 10);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = color.withValues(alpha: .08),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _CurvePainter old) => true;
}

Future<AnimationTrack?> _animationDialog(
  BuildContext context,
  AnimationTrack? original,
) async {
  var property = original?.property ?? AnimationProperty.scale;
  var enabled = original?.enabled ?? true;
  var keys = [...?original?.keyframes];
  if (keys.isEmpty) {
    keys = [
      const Keyframe(timeUs: 0, value: 1),
      const Keyframe(timeUs: 1000000, value: 1.2),
    ];
  }
  final form = GlobalKey<FormState>();
  String? error;
  return showDialog<AnimationTrack>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Ключевые кадры'),
        scrollable: true,
        content: SizedBox(
          width: 440,
          child: Form(
            key: form,
            onChanged: () => setState(() {}),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  title: const Text("Анимация включена"),
                  value: enabled,
                  onChanged: (v) => setState(() => enabled = v),
                ),
                DropdownButtonFormField<AnimationProperty>(
                  initialValue: property,
                  decoration: const InputDecoration(labelText: 'Параметр'),
                  items: [
                    for (final p in AnimationProperty.values)
                      DropdownMenuItem(value: p, child: Text(p.name)),
                  ],
                  onChanged: (v) => setState(() => property = v!),
                ),
                CurveGraph(
                  track: AnimationTrack(
                    id: 'graph',
                    property: property,
                    keyframes: keys,
                  ),
                ),
                for (var i = 0; i < keys.length; i++)
                  Card(
                    key: ValueKey('$i-${keys.length}'),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        children: [
                          Text('Ключ ${i + 1}'),
                          _number(
                            'Время ключа ${i + 1}, с',
                            keys[i].timeUs / 1000000,
                            0,
                            3600,
                            (v) => keys[i] = Keyframe(
                              timeUs: (v * 1000000).round(),
                              value: keys[i].value,
                              interpolation: keys[i].interpolation,
                              bezier: keys[i].bezier,
                            ),
                          ),
                          _number(
                            'Значение ключа ${i + 1}',
                            keys[i].value,
                            -10000,
                            10000,
                            (v) => keys[i] = Keyframe(
                              timeUs: keys[i].timeUs,
                              value: v,
                              interpolation: keys[i].interpolation,
                              bezier: keys[i].bezier,
                            ),
                          ),
                          DropdownButtonFormField<Interpolation>(
                            initialValue: keys[i].interpolation,
                            decoration: const InputDecoration(
                              labelText: 'Интерполяция',
                            ),
                            items: [
                              for (final c in Interpolation.values)
                                DropdownMenuItem(value: c, child: Text(c.name)),
                            ],
                            onChanged: (v) => setState(
                              () => keys[i] = Keyframe(
                                timeUs: keys[i].timeUs,
                                value: keys[i].value,
                                interpolation: v!,
                                bezier: keys[i].bezier,
                              ),
                            ),
                          ),
                          if (keys[i].interpolation ==
                              Interpolation.cubicBezier)
                            for (var b = 0; b < 4; b++)
                              _number(
                                'Bezier ${i + 1}: ${['x1', 'y1', 'x2', 'y2'][b]}',
                                keys[i].bezier[b],
                                b.isEven ? 0 : -10,
                                b.isEven ? 1 : 10,
                                (v) {
                                  final controls = [...keys[i].bezier]..[b] = v;
                                  keys[i] = Keyframe(
                                    timeUs: keys[i].timeUs,
                                    value: keys[i].value,
                                    interpolation: keys[i].interpolation,
                                    bezier: controls,
                                  );
                                },
                              ),
                          TextButton(
                            onPressed: keys.length <= 1
                                ? null
                                : () => setState(() => keys.removeAt(i)),
                            child: const Text('Удалить ключ'),
                          ),
                        ],
                      ),
                    ),
                  ),
                TextButton(
                  onPressed: () => setState(
                    () => keys.add(
                      Keyframe(
                        timeUs: (keys.last.timeUs + 500000),
                        value: keys.last.value,
                      ),
                    ),
                  ),
                  child: const Text('Добавить ключ'),
                ),
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              if (!form.currentState!.validate()) return;
              final sorted = [...keys]
                ..sort((a, b) => a.timeUs.compareTo(b.timeUs));
              final track = AnimationTrack(
                id:
                    original?.id ??
                    'animation-${DateTime.now().microsecondsSinceEpoch}',
                property: property,
                keyframes: sorted,
                enabled: enabled,
              );
              try {
                track.validate();
                Navigator.pop(context, track);
              } on FormatException {
                setState(
                  () => error = 'Время каждого ключа должно быть уникальным',
                );
              }
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    ),
  );
}
