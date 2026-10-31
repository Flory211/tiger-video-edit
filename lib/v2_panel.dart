import 'package:flutter/material.dart';

import 'editor.dart';
import 'model.dart';

/// Additional properties, embedded in the editor's existing properties list.
class V2Panel extends StatefulWidget {
  final Editor editor;
  const V2Panel({super.key, required this.editor});

  @override
  State<V2Panel> createState() => _V2PanelState();
}

class _V2PanelState extends State<V2Panel> {
  String? _preset;
  Editor get editor => widget.editor;
  static const _effects = {
    'shake': 'Тряска',
    'zoom': 'Приближение',
    'blur': 'Размытие',
    'glow': 'Свечение',
    'flash': 'Вспышка',
    'rgb': 'Сдвиг RGB',
    'glitch': 'Глитч',
  };

  Future<void> _savePreset() async {
    var enteredName = '';
    final form = GlobalKey<FormState>();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Сохранить пресет'),
        content: Form(
          key: form,
          child: TextFormField(
            autofocus: true,
            maxLength: 60,
            onChanged: (value) => enteredName = value,
            decoration: const InputDecoration(
              labelText: 'Название',
              helperText: 'Существующее имя заменит пресет',
              helperMaxLines: 2,
            ),
            validator: (text) =>
                (text ?? '').trim().isEmpty ? 'Введите название' : null,
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
                Navigator.pop(context, enteredName.trim());
              }
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (!mounted || name == null) return;
    await editor.guard(() => editor.savePreset(name));
    if (mounted && editor.presets.containsKey(name)) {
      setState(() => _preset = name);
    }
  }

  Future<void> _caption([Caption? caption]) async {
    final start = editor.positionUs.clamp(0, editor.project.durationUs);
    final limit = editor.project.durationUs;
    final proposedEnd = start + 2000000;
    final result = await showDialog<Caption>(
      context: context,
      builder: (context) => _CaptionDialog(
        caption:
            caption ??
            Caption(
              id: 'caption-${DateTime.now().microsecondsSinceEpoch}',
              text: '',
              startUs: start < limit ? start : editor.project.startUs,
              endUs: proposedEnd > limit ? limit : proposedEnd,
            ),
        durationUs: limit,
        isNew: caption == null,
      ),
    );
    if (mounted && result != null) editor.upsertCaption(result);
  }

  Widget _slider(
    String label,
    double value,
    ValueChanged<double> onChanged, {
    double min = 0,
    double max = 1,
    String? display,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('$label: ${display ?? '${(value * 100).round()}%'}'),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          label: display ?? '${(value * 100).round()}%',
          onChanged: onChanged,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: editor,
    builder: (context, _) {
      final images = editor.project.images;
      final index = editor.selectedImage;
      final still = index >= 0 && index < images.length ? images[index] : null;
      final names = editor.presets.keys.toList();
      final selected = names.contains(_preset) ? _preset : null;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (still != null) ...[
            const Divider(),
            const Text(
              'ЭФФЕКТЫ',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            for (final effect in _effects.entries)
              _slider(effect.value, still.effects[effect.key] ?? 0, (value) {
                editor.updateStill(
                  still.copy(effects: {...still.effects, effect.key: value}),
                );
              }),
            _slider(
              'Длительность',
              still.effectDurationUs / 1000000,
              (value) => editor.updateStill(
                still.copy(effectDurationUs: (value * 1000000).round()),
              ),
              min: .05,
              max: 5,
              display:
                  '${(still.effectDurationUs / 1000000).toStringAsFixed(2)} с',
            ),
            DropdownButtonFormField<String>(
              key: ValueKey(selected),
              initialValue: selected,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Пресет'),
              items: [
                for (final name in names)
                  DropdownMenuItem(
                    value: name,
                    child: Text(name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (value) => setState(() => _preset = value),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              children: [
                TextButton(
                  onPressed: selected == null
                      ? null
                      : () => editor.applyPreset(selected),
                  child: const Text('Применить'),
                ),
                TextButton(
                  onPressed: selected == null
                      ? null
                      : () => editor.applyPreset(selected, all: true),
                  child: const Text('Пресет для всех'),
                ),
                TextButton(
                  onPressed: _savePreset,
                  child: const Text('Сохранить текущие'),
                ),
                TextButton(
                  onPressed: editor.setEffectsForAll,
                  child: const Text('Текущие эффекты для всех'),
                ),
              ],
            ),
            if (still.kind == 'video' || still.kind == 'gif') ...[
              const SizedBox(height: 8),
              _SourceStartField(
                key: ValueKey('$index:${still.path}:${still.sourceStartUs}'),
                still: still,
                onApply: (value) =>
                    editor.updateStill(still.copy(sourceStartUs: value)),
              ),
            ],
          ],
          const Divider(),
          const Text('ТИТРЫ', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          const Text(
            'Время от начала исходного аудио',
            style: TextStyle(fontSize: 12, color: Colors.white60),
          ),
          for (final caption in editor.project.captions)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      style: TextButton.styleFrom(
                        alignment: Alignment.centerLeft,
                      ),
                      onPressed: () => _caption(caption),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            caption.text,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${(caption.startUs / 1000000).toStringAsFixed(2)}–'
                            '${(caption.endUs / 1000000).toStringAsFixed(2)} с',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Удалить титр',
                    onPressed: () => editor.deleteCaption(caption.id),
                    icon: const Icon(Icons.delete_outline, size: 19),
                  ),
                ],
              ),
            ),
          TextButton.icon(
            onPressed: editor.project.durationUs > 0 ? () => _caption() : null,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Добавить титр'),
          ),
        ],
      );
    },
  );
}

double? _number(String text) =>
    double.tryParse(text.trim().replaceAll(',', '.'));

class _SourceStartField extends StatefulWidget {
  final Still still;
  final ValueChanged<int> onApply;
  const _SourceStartField({
    super.key,
    required this.still,
    required this.onApply,
  });

  @override
  State<_SourceStartField> createState() => _SourceStartFieldState();
}

class _SourceStartFieldState extends State<_SourceStartField> {
  final _form = GlobalKey<FormState>();
  late final _controller = TextEditingController(
    text: (widget.still.sourceStartUs / 1000000).toStringAsFixed(3),
  );

  void _apply() {
    if (_form.currentState!.validate()) {
      widget.onApply((_number(_controller.text)! * 1000000).round());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Form(
    key: _form,
    child: TextFormField(
      controller: _controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: 'Начало клипа, с',
        errorMaxLines: 3,
        suffixIcon: IconButton(
          tooltip: 'Применить начало клипа',
          onPressed: _apply,
          icon: const Icon(Icons.check),
        ),
      ),
      validator: (text) {
        final value = _number(text ?? '');
        if (value == null ||
            !value.isFinite ||
            value < 0 ||
            value > 2147483647) {
          return 'Введите неотрицательное число';
        }
        if (widget.still.durationUs > 0 &&
            (value * 1000000).round() >= widget.still.durationUs) {
          return 'Начало должно быть раньше конца клипа';
        }
        return null;
      },
      onFieldSubmitted: (_) => _apply(),
    ),
  );
}

class _CaptionDialog extends StatefulWidget {
  final Caption caption;
  final int durationUs;
  final bool isNew;
  const _CaptionDialog({
    required this.caption,
    required this.durationUs,
    required this.isNew,
  });

  @override
  State<_CaptionDialog> createState() => _CaptionDialogState();
}

class _CaptionDialogState extends State<_CaptionDialog> {
  final _form = GlobalKey<FormState>();
  late final _text = TextEditingController(text: widget.caption.text);
  late final _start = TextEditingController(
    text: (widget.caption.startUs / 1000000).toStringAsFixed(6),
  );
  late final _end = TextEditingController(
    text: (widget.caption.endUs / 1000000).toStringAsFixed(6),
  );
  late final _x = TextEditingController(text: widget.caption.x.toString());
  late final _y = TextEditingController(text: widget.caption.y.toString());
  late final _size = TextEditingController(
    text: widget.caption.fontSize.toString(),
  );
  late int _color = widget.caption.color;
  static const _colors = {
    0xffffffff: 'Белый',
    0xff000000: 'Чёрный',
    0xffffd54f: 'Жёлтый',
    0xffef5350: 'Красный',
    0xff66bb6a: 'Зелёный',
    0xff42a5f5: 'Синий',
  };

  @override
  void dispose() {
    for (final controller in [_text, _start, _end, _x, _y, _size]) {
      controller.dispose();
    }
    super.dispose();
  }

  Widget _field(
    String label,
    TextEditingController controller,
    double min,
    double max,
  ) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label, errorMaxLines: 3),
      validator: (text) {
        final value = _number(text ?? '');
        if (value == null || !value.isFinite || value < min || value > max) {
          return 'Введите число от $min до $max';
        }
        if (controller == _end) {
          final start = _number(_start.text);
          if (start != null &&
              start.isFinite &&
              (value * 1000000).round() <= (start * 1000000).round()) {
            return 'Конец должен быть позже начала';
          }
        }
        return null;
      },
    ),
  );

  void _save() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(
      context,
      widget.caption.copy(
        text: _text.text.trim(),
        startUs: (_number(_start.text)! * 1000000).round(),
        endUs: (_number(_end.text)! * 1000000).round(),
        x: _number(_x.text),
        y: _number(_y.text),
        fontSize: _number(_size.text),
        color: _color,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.isNew ? 'Добавить титр' : 'Изменить титр'),
    content: SizedBox(
      width: 360,
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _text,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(labelText: 'Текст'),
                validator: (value) =>
                    (value ?? '').trim().isEmpty ? 'Введите текст титра' : null,
              ),
              _field(
                'Начало, с исходного аудио',
                _start,
                0,
                widget.durationUs / 1000000,
              ),
              _field(
                'Конец, с исходного аудио',
                _end,
                0,
                widget.durationUs / 1000000,
              ),
              _field('Горизонталь (0–1)', _x, 0, 1),
              _field('Вертикаль (0–1)', _y, 0, 1),
              _field('Размер шрифта, пиксели', _size, 8, 300),
              const SizedBox(height: 12),
              const Text('Цвет текста'),
              Wrap(
                spacing: 4,
                children: [
                  for (final entry in _colors.entries)
                    Tooltip(
                      message: entry.value,
                      child: ChoiceChip(
                        label: Text(entry.value),
                        avatar: CircleAvatar(
                          backgroundColor: Color(entry.key),
                          radius: 7,
                        ),
                        selected: _color == entry.key,
                        onSelected: (_) => setState(() => _color = entry.key),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      FilledButton(onPressed: _save, child: const Text('Сохранить')),
    ],
  );
}
