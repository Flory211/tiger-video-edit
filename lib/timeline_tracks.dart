import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'editor.dart';
import 'model.dart';
import 'v3_panel.dart';

class TimelineTracks extends StatelessWidget {
  final Editor editor;
  const TimelineTracks({super.key, required this.editor});
  @override
  Widget build(BuildContext context) {
    final e = editor, p = e.project;
    final rows =
        <
          ({
            String label,
            Color color,
            List<
              ({
                String id,
                int start,
                int duration,
                String title,
                VoidCallback edit,
                void Function(int) move,
              })
            >
            clips,
          })
        >[];
    for (final track
        in p.visualClips.map((c) => c.track).toSet().toList()..sort()) {
      rows.add((
        label: 'Видео $track',
        color: Colors.blueAccent,
        clips: [
          for (final c in p.visualClips.where((c) => c.track == track))
            (
              id: c.id,
              start: c.startUs,
              duration: c.durationUs,
              title: c.media.path.replaceAll('\\', '/').split('/').last,
              edit: () => _visual(context, e, c),
              move: (us) => e.updateVisualClip(c.copy(startUs: e.snapTime(us))),
            ),
        ],
      ));
    }
    for (final track
        in p.audioClips.map((c) => c.track).toSet().toList()..sort()) {
      rows.add((
        label: 'Аудио ${track + 1}',
        color: Colors.orangeAccent,
        clips: [
          for (final c in p.audioClips.where((c) => c.track == track))
            (
              id: c.id,
              start: c.startUs,
              duration: c.durationUs,
              title: c.path.replaceAll('\\', '/').split('/').last,
              edit: () => _audio(context, e, c),
              move: (us) => e.updateAudioClip(c.copy(startUs: e.snapTime(us))),
            ),
        ],
      ));
    }
    if (p.globalEffects.isNotEmpty) {
      rows.add((
        label: 'Эффекты',
        color: Colors.purpleAccent,
        clips: [
          for (final c in p.globalEffects)
            (
              id: c.id,
              start: c.mode == GlobalEffectMode.range ? c.startUs : p.startUs,
              duration: c.mode == GlobalEffectMode.range
                  ? c.endUs - c.startUs
                  : p.endUs - p.startUs,
              title: c.effects.map((f) => f.type).join(' + '),
              edit: () => showDialog<void>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Глобальные эффекты'),
                  content: SizedBox(
                    width: 460,
                    height: 430,
                    child: SingleChildScrollView(child: V3Panel(editor: e)),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Закрыть'),
                    ),
                  ],
                ),
              ),
              move: (us) {
                if (c.mode == GlobalEffectMode.range) {
                  final length = c.endUs - c.startUs,
                      start = e.snapTime(us).clamp(p.startUs, p.endUs - length);
                  e.updateGlobalLayer(
                    c.copy(startUs: start, endUs: start + length),
                  );
                }
              },
            ),
        ],
      ));
    }
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      height: math.min(148.0, 44.0 + rows.length * 34),
      child: Column(
        children: [
          SizedBox(
            height: 38,
            child: Row(
              children: [
                const SizedBox(width: 4),
                Text(
                  'ДОРОЖКИ',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Громкость музыки и звуков',
                  onPressed: () => _mixer(context, e),
                  icon: const Icon(Icons.tune, size: 18),
                ),
                const Text('Привязка', style: TextStyle(fontSize: 11)),
                SizedBox(
                  width: 48,
                  child: FittedBox(
                    child: Switch(
                      value: e.snapToMarkers,
                      onChanged: (v) {
                        e.snapToMarkers = v;
                        e.refresh();
                      },
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Добавить изображение в отдельный слой',
                  onPressed: p.images.isEmpty
                      ? null
                      : () => e.addVisualLayer(e.selectedImage),
                  icon: const Icon(Icons.layers_outlined, size: 18),
                ),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: math.max(box.maxWidth, box.maxWidth * e.zoom),
                    child: ListView(
                      children: [
                        for (final row in rows)
                          SizedBox(
                            height: 34,
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 78,
                                  child: Text(
                                    row.label,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: LayoutBuilder(
                                    builder: (context, trackBox) {
                                      return Stack(
                                        children: [
                                          Container(
                                            decoration: BoxDecoration(
                                              border: Border(
                                                bottom: BorderSide(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .outlineVariant,
                                                ),
                                              ),
                                            ),
                                          ),
                                          for (final clip in row.clips)
                                            Positioned(
                                              left:
                                                  clip.start /
                                                  math.max(1, p.durationUs) *
                                                  trackBox.maxWidth,
                                              top: 3,
                                              bottom: 3,
                                              width: math.max(
                                                26,
                                                clip.duration /
                                                    math.max(1, p.durationUs) *
                                                    trackBox.maxWidth,
                                              ),
                                              child: _ClipBlock(
                                                color: row.color,
                                                title: clip.title,
                                                onTap: clip.edit,
                                                onMove: (dx) => clip.move(
                                                  clip.start +
                                                      (dx /
                                                              trackBox
                                                                  .maxWidth *
                                                              p.durationUs)
                                                          .round(),
                                                ),
                                              ),
                                            ),
                                        ],
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
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _mixer(BuildContext context, Editor e) async {
    var music = e.project.musicVolume, sound = e.project.soundVolume;
    final values = await showDialog<(double, double)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: const Text('Громкость групп'),
          scrollable: true,
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Музыка: ${(music * 100).round()}%'),
                Slider(
                  value: music,
                  min: 0,
                  max: 2,
                  divisions: 40,
                  onChanged: (v) => set(() => music = v),
                ),
                Text('Звуковые эффекты: ${(sound * 100).round()}%'),
                Slider(
                  value: sound,
                  min: 0,
                  max: 2,
                  divisions: 40,
                  onChanged: (v) => set(() => sound = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, (music, sound)),
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
    if (values != null) {
      e.change(e.project.copy(musicVolume: values.$1, soundVolume: values.$2));
    }
  }

  Future<void> _audio(BuildContext context, Editor e, AudioClip c) async {
    final result = await _values(
      context,
      'Аудиоклип',
      {
        'Начало, с': c.startUs / 1e6,
        'Начало источника, с': c.sourceStartUs / 1e6,
        'Длительность, с': c.durationUs / 1e6,
        'Громкость, %': c.volume * 100,
        'Fade In, с': c.fadeInUs / 1e6,
        'Fade Out, с': c.fadeOutUs / 1e6,
        'Дорожка': c.track.toDouble(),
      },
      onDelete: () => e.deleteAudioClip(c.id),
      onCopy: () => e.duplicateAudioClip(c),
    );
    if (result == null) return;
    await e.guard(() async {
      e.updateAudioClip(
        c.copy(
          startUs: (result[0] * 1e6).round(),
          sourceStartUs: (result[1] * 1e6).round(),
          durationUs: (result[2] * 1e6).round(),
          volume: result[3] / 100,
          fadeInUs: (result[4] * 1e6).round(),
          fadeOutUs: (result[5] * 1e6).round(),
          track: result[6].round(),
        ),
      );
    });
  }

  Future<void> _visual(BuildContext context, Editor e, VisualClip c) async {
    final result = await _values(context, 'Визуальный слой', {
      'Начало, с': c.startUs / 1e6,
      'Длительность, с': c.durationUs / 1e6,
      'Непрозрачность, %': c.opacity * 100,
      'Масштаб': c.media.scale,
      'X, доля кадра': c.media.x,
      'Y, доля кадра': c.media.y,
      'Дорожка': c.track.toDouble(),
    }, onDelete: () => e.deleteVisualClip(c.id));
    if (result == null) return;
    await e.guard(() async {
      e.updateVisualClip(
        c.copy(
          startUs: (result[0] * 1e6).round(),
          durationUs: (result[1] * 1e6).round(),
          opacity: result[2] / 100,
          media: c.media.copy(scale: result[3], x: result[4], y: result[5]),
          track: result[6].round(),
        ),
      );
    });
  }

  Future<List<double>?> _values(
    BuildContext context,
    String title,
    Map<String, double> values, {
    required VoidCallback onDelete,
    VoidCallback? onCopy,
  }) async {
    final fields = values.values
        .map((v) => TextEditingController(text: v.toStringAsFixed(3)))
        .toList();
    final form = GlobalKey<FormState>();
    final result = await showDialog<List<double>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < fields.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: TextFormField(
                      controller: fields[i],
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      decoration: InputDecoration(
                        labelText: values.keys.elementAt(i),
                      ),
                      validator: (s) {
                        final n = double.tryParse(
                          (s ?? '').replaceAll(',', '.'),
                        );
                        return n == null || !n.isFinite
                            ? 'Введите конечное число'
                            : null;
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              onDelete();
              Navigator.pop(ctx);
            },
            child: const Text('Удалить'),
          ),
          if (onCopy != null)
            TextButton(
              onPressed: () {
                onCopy();
                Navigator.pop(ctx);
              },
              child: const Text('Копировать'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(
                  ctx,
                  fields
                      .map((f) => double.parse(f.text.replaceAll(',', '.')))
                      .toList(),
                );
              }
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    for (final c in fields) {
      c.dispose();
    }
    return result;
  }
}

class _ClipBlock extends StatefulWidget {
  final Color color;
  final String title;
  final VoidCallback onTap;
  final void Function(double) onMove;
  const _ClipBlock({
    required this.color,
    required this.title,
    required this.onTap,
    required this.onMove,
  });
  @override
  State<_ClipBlock> createState() => _ClipBlockState();
}

class _ClipBlockState extends State<_ClipBlock> {
  double dx = 0;
  @override
  Widget build(BuildContext context) => Transform.translate(
    offset: Offset(dx, 0),
    child: GestureDetector(
      onTap: widget.onTap,
      onHorizontalDragStart: (_) => dx = 0,
      onHorizontalDragUpdate: (d) => setState(() => dx += d.delta.dx),
      onHorizontalDragEnd: (_) {
        widget.onMove(dx);
        setState(() => dx = 0);
      },
      child: Tooltip(
        message: widget.title,
        child: Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: .32),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: widget.color),
          ),
          child: Text(
            widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10),
          ),
        ),
      ),
    ),
  );
}
