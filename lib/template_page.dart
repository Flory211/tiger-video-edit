import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'media_bridge.dart';

import 'editor.dart';
import 'model.dart' show EffectInstance;
import 'edit_templates.dart';

class TemplatesPage extends StatefulWidget {
  final Editor editor;
  final TemplateStore? store;
  const TemplatesPage({super.key, required this.editor, this.store});
  @override
  State<TemplatesPage> createState() => _TemplatesPageState();
}

enum _Action { apply, duplicate, rename, export, delete }

class _TemplatesPageState extends State<TemplatesPage> {
  late final TemplateStore store =
      widget.store ??
      TemplateStore(Directory('${widget.editor.library.root.path}/templates'));
  List<EditTemplate> own = [];
  bool busy = false;
  String search = '';
  @override
  void initState() {
    super.initState();
    _run(_load);
  }

  Future<void> _load() async {
    final loaded = await store.load();
    if (mounted) {
      setState(() => own = loaded..sort((a, b) => a.name.compareTo(b.name)));
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String _id() => 'user_${DateTime.now().microsecondsSinceEpoch}';
  Future<void> _saveCurrent() async {
    final p = widget.editor.project, index = widget.editor.selectedImage;
    final item = index >= 0 && index < p.images.length ? p.images[index] : null;
    final base = EditTemplate(
      id: _id(),
      name: 'Мой эдит',
      portrait: p.portrait,
      effects: [
        if (item != null) ...[
          for (final entry in item.effects.entries)
            if (entry.value > 0)
              EffectInstance(
                id: 'legacy_${entry.key}',
                type: entry.key,
                strength: entry.value,
                durationUs: item.effectDurationUs,
              ),
          ...item.effectStack,
        ],
      ],
      animations: item?.animations ?? [],
      globalEffects: p.globalEffects,
    );
    base.validate();
    final edited = await _edit(context, base);
    if (edited == null) return;
    await store.save(edited);
    await _load();
  }

  Future<void> _import() async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(
          label: 'Tiger template JSON',
          extensions: ['json'],
          mimeTypes: ['application/json'],
        ),
      ],
    );
    if (file == null) return;
    final imported = await store.read(File(file.path));
    await store.save(imported.copy(id: _id()));
    await _load();
  }

  Future<void> _export(EditTemplate template) async {
    final json = const JsonEncoder.withIndent('  ').convert(template.toJson());
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      final target = await getSaveLocation(
        suggestedName: '${template.id}.json',
        acceptedTypeGroups: [
          const XTypeGroup(label: 'Tiger template JSON', extensions: ['json']),
        ],
      );
      if (target == null) return;
      await File(target.path).writeAsString(json, flush: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Шаблон сохранён: ${target.path}')),
        );
      }
    } else {
      final exports = TemplateStore(Directory('${store.root.path}/exports'));
      await exports.save(template);
      final uri = await nativeMedia.invokeMethod<String>('saveDocument', {
        'path': '${exports.root.path}/${template.id}.json',
        'name': '${template.id}.json',
        'mime': 'application/json',
      });
      if (uri != null && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Шаблон экспортирован')));
      }
    }
  }

  Future<void> _action(
    _Action action,
    EditTemplate template,
    bool isOwn,
  ) async {
    switch (action) {
      case _Action.apply:
        await widget.editor.applyTemplate(template);
        if (!mounted) return;
        if (widget.editor.pendingTemplate != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Шаблон применится после добавления музыки и изображений',
              ),
            ),
          );
        }
        if (Navigator.of(context).canPop()) Navigator.pop(context);
      case _Action.duplicate:
        final name = '${template.name} — копия';
        await store.save(
          template.copy(
            id: _id(),
            name: name.length > 120 ? name.substring(0, 120) : name,
          ),
        );
        await _load();
      case _Action.rename:
        if (!isOwn) return;
        final edited = await _edit(context, template, renameOnly: true);
        if (edited == null) return;
        await store.save(edited);
        await _load();
      case _Action.export:
        await _export(template);
      case _Action.delete:
        if (!isOwn) return;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Удалить свой шаблон?'),
            content: Text(template.name),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Удалить'),
              ),
            ],
          ),
        );
        if (confirmed == true) {
          await store.delete(template);
          await _load();
        }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Шаблоны эдитов'),
      actions: [
        IconButton(
          tooltip: 'Импорт JSON',
          onPressed: busy ? null : () => _run(_import),
          icon: const Icon(Icons.file_open_outlined),
        ),
        IconButton(
          tooltip: 'Сохранить текущий монтаж',
          onPressed: busy ? null : () => _run(_saveCurrent),
          icon: const Icon(Icons.add_box_outlined),
        ),
      ],
    ),
    body: Column(
      children: [
        if (busy)
          const Padding(padding: EdgeInsets.all(8), child: Text('Обработка…')),
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: const InputDecoration(
              labelText: 'Поиск шаблона',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => search = v),
          ),
        ),
        if (widget.editor.project.audio == null ||
            widget.editor.project.images.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Выберите шаблон сейчас: он применится после добавления музыки и изображений.',
            ),
          ),
        Expanded(
          child: ListView(
            children: [
              for (final section in [false, true]) ...[
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    section ? 'МОИ ШАБЛОНЫ' : 'ВСТРОЕННЫЕ ШАБЛОНЫ',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                if (section && own.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Сохраните текущий монтаж или импортируйте JSON',
                    ),
                  ),
                for (final t in (section ? own : builtinEditTemplates).where(
                  (t) => t.name.toLowerCase().contains(search.toLowerCase()),
                ))
                  Card(
                    child: ListTile(
                      title: Text(t.name),
                      subtitle: Text(
                        '${t.profile} • шаг ${t.beatStep}\n${t.effects.length} эффектов • ${t.animations.length} анимаций • ${t.globalEffects.length} глобальных слоёв',
                      ),
                      isThreeLine: true,
                      onTap: busy
                          ? null
                          : () =>
                                _run(() => _action(_Action.apply, t, section)),
                      trailing: PopupMenuButton<_Action>(
                        tooltip: 'Действия: ${t.name}',
                        enabled: !busy,
                        onSelected: (action) =>
                            _run(() => _action(action, t, section)),
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: _Action.apply,
                            child: Text('Применить'),
                          ),
                          const PopupMenuItem(
                            value: _Action.duplicate,
                            child: Text('Дублировать'),
                          ),
                          const PopupMenuItem(
                            value: _Action.export,
                            child: Text('Экспорт JSON'),
                          ),
                          if (section) ...[
                            const PopupMenuItem(
                              value: _Action.rename,
                              child: Text('Переименовать'),
                            ),
                            const PopupMenuItem(
                              value: _Action.delete,
                              child: Text('Удалить'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

Future<EditTemplate?> _edit(
  BuildContext context,
  EditTemplate template, {
  bool renameOnly = false,
}) async {
  final form = GlobalKey<FormState>();
  var name = template.name,
      profile = template.profile,
      beatStep = template.beatStep;
  var portrait = template.portrait;
  return showDialog<EditTemplate>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(
          renameOnly ? 'Переименовать шаблон' : 'Сохранить монтаж как шаблон',
        ),
        scrollable: true,
        content: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                initialValue: name,
                maxLength: 120,
                decoration: const InputDecoration(labelText: 'Название'),
                onChanged: (v) => name = v,
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Введите название' : null,
              ),
              if (!renameOnly) ...[
                DropdownButtonFormField<String>(
                  initialValue: profile,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Профиль Auto Edit',
                  ),
                  items: [
                    for (final p in autoEditProfiles)
                      DropdownMenuItem(value: p, child: Text(p)),
                  ],
                  onChanged: (v) => profile = v!,
                ),
                TextFormField(
                  initialValue: '$beatStep',
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Шаг музыкальных маркеров',
                  ),
                  onChanged: (v) => beatStep = int.tryParse(v) ?? 0,
                  validator: (v) {
                    final n = int.tryParse(v ?? '');
                    return n == null || n < 1 || n > 8
                        ? 'Допустимо от 1 до 8'
                        : null;
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Вертикальный формат'),
                  value: portrait,
                  onChanged: (v) => setState(() => portrait = v),
                ),
                Text(
                  'Сохраняется стек выбранной картинки, её анимации и все глобальные слои.',
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
              final next = EditTemplate(
                id: template.id,
                name: name.trim(),
                profile: profile,
                portrait: portrait,
                beatStep: beatStep,
                effects: template.effects,
                animations: template.animations,
                globalEffects: template.globalEffects,
              );
              next.validate();
              Navigator.pop(context, next);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    ),
  );
}
