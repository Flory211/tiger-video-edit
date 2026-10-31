import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';
import 'package:media_kit/media_kit.dart';

import 'editor.dart';
import 'model.dart';
import 'platform_media.dart';
import 'media_frames.dart';
import 'v2_panel.dart';
import 'storage.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    MediaKit.ensureInitialized();
    final editor = Editor(await LocalLibrary.open(), AudioEngine());
    await editor.initialize();
    runApp(TigerApp(editor: editor));
    if (args.isNotEmpty) {
      await editor.guard(() => editor.openProject(args.first));
    }
  } catch (e) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SelectableText('Не удалось запустить медиадвижок: $e'),
          ),
        ),
      ),
    );
  }
}

const accent = Color(0xffc6f36a), panel = Color(0xff191c22);
String labelPath(String? path) =>
    path?.replaceAll('\\', '/').split('/').last ?? 'Музыка не добавлена';
String clockTime(int us) {
  final ms = us ~/ 1000;
  return '${(ms ~/ 60000).toString().padLeft(2, '0')}:${(ms ~/ 1000 % 60).toString().padLeft(2, '0')}.${(ms % 1000).toString().padLeft(3, '0')}';
}

class TigerApp extends StatelessWidget {
  final Editor editor;
  const TigerApp({super.key, required this.editor});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Tiger Video Edit',
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xff101217),
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.dark,
        primary: accent,
        surface: panel,
      ),
      sliderTheme: const SliderThemeData(trackHeight: 3),
      inputDecorationTheme: const InputDecorationTheme(
        isDense: true,
        border: OutlineInputBorder(),
      ),
    ),
    home: EditorScreen(editor: editor),
  );
}

class EditorScreen extends StatefulWidget {
  final Editor editor;
  const EditorScreen({super.key, required this.editor});
  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen>
    with WidgetsBindingObserver {
  Editor get e => widget.editor;
  int mobileTab = 0;
  int _lastPreviewIndex = -2;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_key);
    e.addListener(_update);
  }

  void _update() {
    final index = e.project.imageIndexAt(e.positionUs);
    if (index != _lastPreviewIndex) {
      _lastPreviewIndex = index;
      final frame = math.max(
        0,
        (e.positionUs - e.project.startUs) * fps ~/ 1000000,
      );
      final paths = e.project.segments
          .where((s) => s.startFrame + s.frameCount > frame)
          .map((s) => e.project.images[s.imageIndex])
          .where((s) => s.kind == 'image')
          .map((s) => s.path);
      previewImages.prepare(paths).catchError((_) {});
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    e.removeListener(_update);
    HardwareKeyboard.instance.removeHandler(_key);
    WidgetsBinding.instance.removeObserver(this);
    e.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive && e.dirty && !e.exporting) {
      e.guard(() => e.save(autosave: true));
    }
    if (state == AppLifecycleState.paused) e.guard(e.stop);
  }

  bool _key(KeyEvent event) {
    if (event is! KeyDownEvent ||
        FocusManager.instance.primaryFocus?.context?.widget is EditableText) {
      return false;
    }
    final focus = FocusManager.instance.primaryFocus;
    if (focus?.context?.findAncestorWidgetOfExactType<EditableText>() != null) {
      return false;
    }
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    if (event.logicalKey == LogicalKeyboardKey.space) {
      e.guard(e.toggle);
      return true;
    }
    if (event.logicalKey.keyLabel.toUpperCase() == e.markerKey.toUpperCase() &&
        !ctrl) {
      e.guard(e.capture);
      return true;
    }
    if (ctrl && event.logicalKey == LogicalKeyboardKey.keyS) {
      e.guard(() => e.save());
      return true;
    }
    if (ctrl && event.logicalKey == LogicalKeyboardKey.keyZ) {
      e.guard(e.undo);
      return true;
    }
    if (ctrl && event.logicalKey == LogicalKeyboardKey.keyY) {
      e.guard(e.redo);
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.delete &&
        e.selectedMarker != null) {
      e.deleteMarker();
      return true;
    }
    return false;
  }

  Widget action(
    String text,
    IconData icon,
    VoidCallback? callback, {
    bool filled = false,
  }) => filled
      ? FilledButton.icon(
          onPressed: callback,
          icon: Icon(icon, size: 18),
          label: Text(text),
        )
      : TextButton.icon(
          onPressed: callback,
          icon: Icon(icon, size: 18),
          label: Text(text),
        );
  Future<void> newProject() async {
    final name = await textDialog('Новый проект', 'Название', 'Мой эдит');
    if (name == null) return;
    await e.guard(() async {
      if (e.dirty) await e.save(autosave: true);
      await e.newProject(name);
    });
  }

  Future<String?> textDialog(String title, String label, String value) async {
    final controller = TextEditingController(text: value);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
          onSubmitted: (v) {
            if (v.trim().isNotEmpty) Navigator.pop(ctx, v.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(ctx, controller.text.trim());
              }
            },
            child: const Text('Готово'),
          ),
        ],
      ),
    );
    // Route teardown may still reference the controller until the next frame.
    Future<void>.delayed(const Duration(milliseconds: 400), controller.dispose);
    return result;
  }

  Future<void> open([String? path]) => e.guard(() async {
    if (e.dirty) await e.save(autosave: true);
    await e.openProject(path);
    final current = e.projectPath;
    if (current != null && !current.endsWith('.autosave')) {
      final recovery = File('$current.autosave');
      if (await recovery.exists() &&
          (await recovery.lastModified()).isAfter(
            await File(current).lastModified(),
          ) &&
          mounted) {
        final restore = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Найдена автокопия'),
            content: const Text(
              'Открыть более новую автоматически сохранённую версию?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Оставить основную'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Восстановить'),
              ),
            ],
          ),
        );
        if (restore == true) {
          await e.openProject(recovery.path);
          e.projectPath = current;
          e.dirty = true;
        }
      }
    }
  });
  Future<void> settings() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Настройки'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  initialValue: e.markerKey,
                  maxLength: 1,
                  decoration: const InputDecoration(
                    labelText: 'Клавиша маркера',
                  ),
                  onChanged: (v) {
                    if (RegExp(r'^[a-zA-Z0-9]$').hasMatch(v)) {
                      e.markerKey = v.toUpperCase();
                    }
                  },
                ),
                SwitchListTile(
                  title: const Text('Отсчёт 3, 2, 1'),
                  value: e.countdown,
                  onChanged: (v) => set(() => e.countdown = v),
                ),
                Text('Автосохранение: ${e.autosaveSeconds} сек.'),
                Slider(
                  value: e.autosaveSeconds.toDouble(),
                  min: 10,
                  max: 600,
                  divisions: 59,
                  onChanged: (v) => set(() => e.autosaveSeconds = v.round()),
                ),
                const Text(
                  'MP4 • H.264 / AAC • 30 FPS\n1920 × 1080 или 1080 × 1920',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Маркеры действуют только в активном окне. Погрешность нажатия зависит от устройства.',
                  style: TextStyle(fontSize: 12, color: Colors.white54),
                ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
    await e.guard(e.preferences);
    e.refresh();
  }

  Future<void> relink() async {
    for (final path in {
      if (e.project.audio != null) e.project.audio!,
      ...e.project.images.map((s) => s.path),
    }) {
      if (!mounted) return;
      final replace = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(labelPath(path)),
          content: SelectableText(path),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Пропустить'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Указать новый файл'),
            ),
          ],
        ),
      );
      if (replace == true) {
        final file = await openFile();
        if (file != null) await e.guard(() => e.relink(path, file.path));
      }
    }
  }

  Future<void> export() async {
    await e.guard(e.exportVideo);
    if (mounted && e.progress == 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('MP4 создан и прошёл базовую проверку.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 950;
    final locked = e.busy || e.exporting;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'TIGER',
              style: TextStyle(
                letterSpacing: 5,
                fontWeight: FontWeight.w800,
                fontSize: 20,
                color: accent,
              ),
            ),
            Text(
              '${e.project.name}${e.dirty ? ' •' : ''}',
              style: const TextStyle(fontSize: 12, color: Colors.white60),
            ),
          ],
        ),
        actions: [
          if (!compact)
            const Text(
              'Tiger Video Edit',
              style: TextStyle(color: Colors.white54),
            ),
          IconButton(
            tooltip: 'Сохранить (Ctrl+S)',
            onPressed: locked ? null : () => e.guard(() => e.save()),
            icon: const Icon(Icons.save_outlined),
          ),
          IconButton(
            tooltip: 'Настройки',
            onPressed: locked ? null : settings,
            icon: const Icon(Icons.tune),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: action(
              'Экспорт',
              Icons.file_upload_outlined,
              locked ? null : export,
              filled: true,
            ),
          ),
          PopupMenuButton<String>(
            enabled: !locked,
            onSelected: (v) {
              switch (v) {
                case 'new':
                  newProject();
                case 'open':
                  open();
                case 'as':
                  e.guard(() => e.save(saveAs: true));
                case 'rename':
                  textDialog('Имя проекта', 'Название', e.project.name).then((
                    v,
                  ) {
                    if (v != null) e.change(e.project.copy(name: v));
                  });
                case 'beats':
                  beats();
                case 'relink':
                  relink();
                case 'recent':
                  showRecent();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'new', child: Text('Новый проект')),
              const PopupMenuItem(value: 'open', child: Text('Открыть проект')),
              const PopupMenuItem(
                value: 'recent',
                child: Text('Последние проекты'),
              ),
              const PopupMenuItem(value: 'as', child: Text('Сохранить как…')),
              const PopupMenuItem(
                value: 'beats',
                child: Text('Ритм и автосборка'),
              ),
              const PopupMenuItem(
                value: 'rename',
                child: Text('Переименовать'),
              ),
              const PopupMenuItem(
                value: 'relink',
                child: Text('Восстановить пути'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (e.error != null)
            Material(
              color: const Color(0xff492b2b),
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Text(
                        e.error!,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      e.error = null;
                      e.refresh();
                    },
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          if (e.busy) const LinearProgressIndicator(),
          if (e.exporting)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Экспорт ${(e.progress * 100).round()}%'),
                        LinearProgressIndicator(value: e.progress),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: e.exporter.cancel,
                    child: const Text('Отменить'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: AbsorbPointer(
              absorbing: locked,
              child: compact
                  ? IndexedStack(
                      index: mobileTab,
                      children: [preview(), library(), properties()],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(width: 238, child: library()),
                        Expanded(child: preview()),
                        SizedBox(width: 260, child: properties()),
                      ],
                    ),
            ),
          ),
          AbsorbPointer(absorbing: locked, child: timeline(compact)),
        ],
      ),
      bottomNavigationBar: compact
          ? NavigationBar(
              selectedIndex: mobileTab,
              onDestinationSelected: (i) => setState(() => mobileTab = i),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.play_circle_outline),
                  label: 'Просмотр',
                ),
                NavigationDestination(
                  icon: Icon(Icons.photo_library_outlined),
                  label: 'Медиа',
                ),
                NavigationDestination(
                  icon: Icon(Icons.tune),
                  label: 'Свойства',
                ),
              ],
            )
          : null,
    );
  }

  Future<void> beats() async {
    if (e.project.audio == null) {
      e.error = 'Сначала добавьте музыку';
      e.refresh();
      return;
    }
    var sensitivity = e.beatSensitivity;
    final analyze = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Ритм и автосборка'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Локальный поиск звуковых атак. Результат можно исправить маркерами; отмена вернёт прежнюю разметку.',
              ),
              const SizedBox(height: 16),
              Text('Чувствительность ${(sensitivity * 100).round()}%'),
              Slider(
                value: sensitivity,
                onChanged: (v) => set(() => sensitivity = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Анализировать'),
            ),
          ],
        ),
      ),
    );
    if (analyze != true) return;
    await e.guard(() => e.analyzeBeats(sensitivity: sensitivity));
    if (!mounted || e.beatAnalysis == null) return;
    final count = e.beatAnalysis!.timesUs
        .where((t) => t > e.project.startUs && t < e.project.endUs)
        .length;
    final bpm = e.beatAnalysis!.bpm;
    final apply = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Найдено $count точек'),
        content: Text(
          '${bpm == null ? 'Темп не определён' : 'Оценка темпа: ${bpm.toStringAsFixed(1)} BPM'}\nАвтосборка заменит текущие маркеры. Медиа останутся в вашем порядке. Алгоритм может принять сильные звуки за доли.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Оставить текущие'),
          ),
          FilledButton(
            onPressed: count == 0 ? null : () => Navigator.pop(ctx, true),
            child: const Text('Автосборка'),
          ),
        ],
      ),
    );
    if (apply == true) {
      await e.guard(() async {
        e.applyBeats();
      });
    }
  }

  void showRecent() {
    showDialog<void>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Последние проекты'),
        children: [
          if (e.recent.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Пока нет сохранённых проектов.'),
            ),
          for (final path in e.recent)
            SimpleDialogOption(
              onPressed: () {
                Navigator.pop(ctx);
                open(path);
              },
              child: Text(labelPath(path)),
            ),
        ],
      ),
    );
  }

  Widget heading(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
    child: Text(
      text,
      style: const TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 13,
        letterSpacing: 1,
      ),
    ),
  );
  Widget library() => Material(
    color: panel,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading('МЕДИАБИБЛИОТЕКА'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: action(
            'Добавить медиа',
            Icons.add_photo_alternate_outlined,
            () => e.guard(e.importImages),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'Порядок = порядок смены\nПеретащите строку за ручку',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ),
        Expanded(
          child: e.project.images.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.photo_library_outlined,
                        size: 40,
                        color: Colors.white24,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Ваши кадры — ваш ритм',
                        style: TextStyle(color: Colors.white54),
                      ),
                      TextButton(
                        onPressed: showRecent,
                        child: const Text('Последние проекты'),
                      ),
                    ],
                  ),
                )
              : ReorderableListView.builder(
                  itemCount: e.project.images.length,
                  onReorderItem: (oldIndex, newIndex) => e.reorder(
                    oldIndex,
                    newIndex > oldIndex ? newIndex + 1 : newIndex,
                  ),
                  itemBuilder: (ctx, i) {
                    final s = e.project.images[i];
                    return ListTile(
                      key: ValueKey('$i:${s.path}'),
                      selected: e.selectedImage == i,
                      selectedTileColor: accent.withValues(alpha: 0.08),
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: s.kind != 'image'
                            ? SizedBox(
                                width: 52,
                                height: 44,
                                child: Icon(
                                  s.kind == 'video'
                                      ? Icons.videocam_outlined
                                      : Icons.gif_box_outlined,
                                ),
                              )
                            : Image.file(
                                File(s.path),
                                width: 52,
                                height: 44,
                                fit: BoxFit.cover,
                                cacheWidth: 128,
                                errorBuilder: (_, err, stack) =>
                                    const Icon(Icons.broken_image),
                              ),
                      ),
                      title: Text(
                        labelPath(s.path),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11),
                      ),
                      subtitle: Text(
                        '${i + 1}'.padLeft(2, '0'),
                        style: const TextStyle(color: Colors.white38),
                      ),
                      onTap: () {
                        e.selectedImage = i;
                        e.inspectImage = true;
                        e.selectedMarker = null;
                        e.refresh();
                      },
                    );
                  },
                ),
        ),
        if (e.project.images.isNotEmpty)
          TextButton.icon(
            onPressed: () {
              final list = [...e.project.images]..removeAt(e.selectedImage);
              e.selectedImage = math.max(
                0,
                math.min(e.selectedImage, list.length - 1),
              );
              e.change(e.project.copy(images: list));
            },
            icon: const Icon(Icons.delete_outline, size: 16),
            label: const Text('Удалить выбранное'),
          ),
      ],
    ),
  );
  Widget preview() {
    final active = e.project.imageIndexAt(e.positionUs);
    final localFrame = math.max(
      0,
      (e.positionUs - e.project.startUs) * fps ~/ 1000000 -
          (e.project.segmentAt(e.positionUs)?.startFrame ?? 0),
    );
    final previewLocalUs = (localFrame * 1000000 + fps - 1) ~/ fps;
    final display = e.project.audio == null || (e.inspectImage && !e.playing)
        ? e.selectedImage
        : active;
    final still = display >= 0 && display < e.project.images.length
        ? e.project.images[display]
        : null;
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.crop_free, size: 14, color: Colors.white38),
              const SizedBox(width: 8),
              const Text(
                'ПРЕДПРОСМОТР',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white54,
                  letterSpacing: 1.5,
                ),
              ),
              const Spacer(),
              DropdownButton<bool>(
                value: e.project.portrait,
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(value: false, child: Text('16:9')),
                  DropdownMenuItem(value: true, child: Text('9:16')),
                ],
                onChanged: (v) => e.change(e.project.copy(portrait: v)),
              ),
            ],
          ),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: e.project.width / e.project.height,
                child: ClipRect(
                  child: ColoredBox(
                    color: Colors.black,
                    child: LayoutBuilder(
                      builder: (ctx, box) => GestureDetector(
                        onPanUpdate: still == null || e.playing
                            ? null
                            : (d) {
                                e.selectedImage = display;
                                e.updateStill(
                                  still.copy(
                                    x: (still.x + d.delta.dx / box.maxWidth)
                                        .clamp(-2, 2),
                                    y: (still.y + d.delta.dy / box.maxHeight)
                                        .clamp(-2, 2),
                                  ),
                                );
                              },
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (still != null)
                              StillView(
                                still: still,
                                project: e.project,
                                sourceUs: e.positionUs,
                                localUs: e.inspectImage && !e.playing
                                    ? 0
                                    : previewLocalUs,
                              )
                            else
                              const Center(
                                child: Text(
                                  'Добавьте музыку и изображения',
                                  style: TextStyle(color: Colors.white38),
                                ),
                              ),
                            if (e.countdownValue > 0)
                              Center(
                                child: Text(
                                  '${e.countdownValue}',
                                  style: const TextStyle(
                                    fontSize: 96,
                                    color: accent,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            clockTime(e.positionUs),
            style: const TextStyle(
              fontFeatures: [ui.FontFeature.tabularFigures()],
              fontSize: 22,
            ),
          ),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            children: [
              IconButton(
                tooltip: 'В начало отрывка',
                onPressed: e.project.audio == null
                    ? null
                    : () => e.guard(() => e.seek(e.project.startUs)),
                icon: const Icon(Icons.skip_previous),
              ),
              FilledButton(
                onPressed: e.project.audio == null
                    ? null
                    : () => e.guard(e.toggle),
                child: Icon(
                  e.playing || e.countdownValue > 0
                      ? Icons.pause
                      : Icons.play_arrow,
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: e.playing ? () => e.guard(e.capture) : null,
                icon: const Icon(Icons.flag_outlined),
                label: Text('Маркер ${e.markerKey}'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Space — воспроизведение • два нажатия на шкале — маркер',
            style: TextStyle(fontSize: 10, color: Colors.white38),
          ),
        ],
      ),
    );
  }

  Widget number(
    String label,
    double value,
    void Function(double) apply, {
    double? min,
    double? max,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: TextFormField(
      key: ValueKey('$label:$value'),
      initialValue: value.toStringAsFixed(3),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label),
      onFieldSubmitted: (text) {
        final v = double.tryParse(text.replaceAll(',', '.'));
        if (v != null &&
            v.isFinite &&
            (min == null || v >= min) &&
            (max == null || v <= max)) {
          apply(v);
        } else {
          e.error = 'Недопустимое значение: $label';
          e.refresh();
        }
      },
    ),
  );
  Widget properties() {
    Marker? marker;
    for (final m in e.project.markers) {
      if (m.id == e.selectedMarker) marker = m;
    }
    final selected = marker;
    final still = e.selectedImage < e.project.images.length
        ? e.project.images[e.selectedImage]
        : null;
    return ColoredBox(
      color: panel,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'СВОЙСТВА',
            style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 1),
          ),
          const SizedBox(height: 18),
          if (selected != null) ...[
            const Text('Выбранный маркер', style: TextStyle(color: accent)),
            number(
              'Позиция, миллисекунды',
              selected.timeUs / 1000,
              (v) => e.moveMarker(selected.id, (v * 1000).round()),
              min: 0,
              max: e.project.durationUs / 1000,
            ),
            action('Удалить маркер', Icons.delete_outline, e.deleteMarker),
            TextButton(
              onPressed: () {
                e.selectedMarker = null;
                e.refresh();
              },
              child: const Text('Снять выбор'),
            ),
            const Divider(),
          ],
          if (still != null) ...[
            Text(
              'Изображение ${e.selectedImage + 1}',
              style: const TextStyle(color: accent),
            ),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: true, label: Text('Заполнить')),
                ButtonSegment(value: false, label: Text('Вписать')),
              ],
              selected: {still.cover},
              onSelectionChanged: (v) =>
                  e.updateStill(still.copy(cover: v.first)),
            ),
            const SizedBox(height: 16),
            Text('Масштаб ${(still.scale * 100).round()}%'),
            Slider(
              value: still.scale,
              min: 0.1,
              max: 8,
              onChanged: (v) => e.updateStill(still.copy(scale: v)),
            ),
            number(
              'Горизонталь, доля кадра',
              still.x,
              (v) => e.updateStill(still.copy(x: v)),
              min: -2,
              max: 2,
            ),
            number(
              'Вертикаль, доля кадра',
              still.y,
              (v) => e.updateStill(still.copy(y: v)),
              min: -2,
              max: 2,
            ),
            TextButton(
              onPressed: () => e.updateStill(Still(path: still.path)),
              child: const Text('Сбросить положение'),
            ),
            const Divider(),
          ],
          V2Panel(editor: e),
          const Divider(),
          const Text(
            'Музыкальный отрывок',
            style: TextStyle(color: Colors.white60),
          ),
          if (e.project.audio != null) ...[
            number(
              'Начало, секунды',
              e.project.startUs / 1000000,
              (v) {
                final start = (v * 1000000).round();
                if (start < e.project.endUs) {
                  e.change(e.project.copy(startUs: start));
                  e.guard(() => e.seek(start));
                }
              },
              min: 0,
              max: e.project.durationUs / 1000000,
            ),
            number(
              'Конец, секунды',
              e.project.endUs / 1000000,
              (v) {
                final end = (v * 1000000).round();
                if (end > e.project.startUs) {
                  e.change(e.project.copy(endUs: end));
                }
              },
              min: 0,
              max: e.project.durationUs / 1000000,
            ),
          ],
          Text(
            '${e.project.width} × ${e.project.height}\n30 FPS • H.264 / AAC',
            style: const TextStyle(fontSize: 12, color: Colors.white38),
          ),
        ],
      ),
    );
  }

  Widget timeline(bool compact) {
    final p = e.project;
    return Container(
      height: compact ? 210 : 240,
      decoration: const BoxDecoration(
        color: Color(0xff15181e),
        border: Border(top: BorderSide(color: Color(0xff30343d))),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Отменить',
                  onPressed: e.history.canUndo ? () => e.guard(e.undo) : null,
                  icon: const Icon(Icons.undo, size: 18),
                ),
                IconButton(
                  tooltip: 'Вернуть',
                  onPressed: e.history.canRedo ? () => e.guard(e.redo) : null,
                  icon: const Icon(Icons.redo, size: 18),
                ),
                Expanded(
                  child: Text(
                    labelPath(p.audio),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                IconButton(
                  tooltip: 'Ритм и автосборка',
                  onPressed: p.audio == null ? null : beats,
                  icon: const Icon(Icons.auto_awesome, size: 20),
                ),
                IconButton(
                  tooltip: 'Импорт музыки',
                  onPressed: () => e.guard(e.importAudio),
                  icon: const Icon(Icons.audio_file_outlined, size: 20),
                ),
                if (!compact)
                  Text(
                    '${p.markers.length} маркеров',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                const Icon(Icons.zoom_in, size: 18),
                SizedBox(
                  width: compact ? 90 : 150,
                  child: Slider(
                    value: math.log(e.zoom) / math.log(200),
                    onChanged: (v) {
                      e.zoom = math.pow(200, v).toDouble();
                      e.refresh();
                    },
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (ctx, box) {
                final width = math.max(box.maxWidth, box.maxWidth * e.zoom);
                final duration = math.max(1, p.durationUs);
                int at(double x) =>
                    (x / width * duration).round().clamp(0, duration);
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: width,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (d) {
                        e.selectedMarker = null;
                        e.guard(() => e.seek(at(d.localPosition.dx)));
                      },
                      onDoubleTapDown: (d) =>
                          e.addMarker(at(d.localPosition.dx)),
                      onLongPressStart: (d) =>
                          e.addMarker(at(d.localPosition.dx)),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: CustomPaint(
                              painter: TimelinePainter(
                                p,
                                e.peaks,
                                e.positionUs,
                                e.zoom,
                              ),
                            ),
                          ),
                          for (final m in p.markers)
                            Positioned(
                              left: m.timeUs / duration * width - 10,
                              top: 25,
                              bottom: 6,
                              child: MarkerHandle(
                                key: ValueKey(m.id),
                                selected: m.id == e.selectedMarker,
                                onSelect: () {
                                  e.selectedMarker = m.id;
                                  e.guard(() => e.seek(m.timeUs));
                                  e.refresh();
                                },
                                onMove: (dx) => e.moveMarker(
                                  m.id,
                                  at(m.timeUs / duration * width + dx),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 3, 12, 8),
            child: Row(
              children: [
                const Icon(Icons.graphic_eq, size: 12, color: accent),
                const SizedBox(width: 8),
                Text(
                  '${clockTime(p.startUs)} — ${clockTime(p.endUs)}',
                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                ),
                const Spacer(),
                Text(
                  '${e.zoom.toStringAsFixed(1)}×',
                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class StillView extends StatefulWidget {
  final Still still;
  final Project project;
  final int localUs, sourceUs;
  const StillView({
    super.key,
    required this.still,
    required this.project,
    this.localUs = 0,
    this.sourceUs = 0,
  });
  @override
  State<StillView> createState() => _StillViewState();
}

class _StillViewState extends State<StillView> {
  ui.Image? image;
  String? error;
  bool loading = false;
  int displayedFrame = -1;
  int displayedStart = -1;
  String? displayedPath;
  final source = MediaFrameSource(maxDimension: 1920);
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(StillView old) {
    super.didUpdateWidget(old);
    if (old.still.path != widget.still.path ||
        old.still.sourceStartUs != widget.still.sourceStartUs ||
        (widget.still.kind != 'image' &&
            old.localUs * fps ~/ 1000000 != widget.localUs * fps ~/ 1000000)) {
      load();
    }
  }

  void load() {
    if (loading) return;
    if (widget.still.kind == 'image') {
      final ready = previewImages.peek(widget.still.path);
      if (ready != null) {
        image?.dispose();
        image = ready.clone();
        displayedPath = widget.still.path;
        displayedStart = widget.still.sourceStartUs;
        error = null;
        return;
      }
    }
    loadAsync();
  }

  Future<void> loadAsync() async {
    loading = true;
    final item = widget.still, time = widget.localUs;
    try {
      final decoded = item.kind == 'image'
          ? (await previewImages.load(item.path)).clone()
          : await source.frame(item, time);
      if (!mounted ||
          widget.still.path != item.path ||
          widget.still.sourceStartUs != item.sourceStartUs) {
        decoded.dispose();
        return;
      }
      final old = image;
      setState(() {
        image = decoded;
        displayedPath = item.path;
        displayedStart = item.sourceStartUs;
        displayedFrame = time * fps ~/ 1000000;
        error = null;
      });
      old?.dispose();
    } catch (e) {
      if (mounted &&
          widget.still.path == item.path &&
          widget.still.sourceStartUs == item.sourceStartUs) {
        setState(() => error = e.toString());
      }
    } finally {
      loading = false;
      if (mounted &&
          (widget.still.path != item.path ||
              widget.still.sourceStartUs != item.sourceStartUs ||
              (widget.still.kind != 'image' &&
                  displayedFrame != widget.localUs * fps ~/ 1000000 &&
                  error == null))) {
        load();
      }
    }
  }

  @override
  void dispose() {
    image?.dispose();
    source.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => error != null
      ? Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Медиа недоступно: $error', maxLines: 5),
          ),
        )
      : image == null ||
            displayedPath != widget.still.path ||
            displayedStart != widget.still.sourceStartUs
      ? const Center(child: CircularProgressIndicator())
      : CustomPaint(
          painter: StillPainter(
            image!,
            widget.still,
            widget.project,
            widget.localUs,
            widget.sourceUs,
          ),
        );
}

class StillPainter extends CustomPainter {
  final ui.Image image;
  final Still still;
  final Project project;
  final int localUs, sourceUs;
  StillPainter(
    this.image,
    this.still,
    this.project,
    this.localUs,
    this.sourceUs,
  );
  @override
  void paint(Canvas canvas, Size size) => paintFrame(
    canvas,
    size,
    image,
    still,
    localUs: localUs,
    sourceUs:
        project.startUs +
        ((sourceUs - project.startUs) * fps ~/ 1000000) * 1000000 ~/ fps,
    captions: project.captions,
    referenceWidth: project.width.toDouble(),
  );
  @override
  bool shouldRepaint(StillPainter old) =>
      old.image != image ||
      old.still != still ||
      old.localUs != localUs ||
      old.sourceUs != sourceUs ||
      old.project != project;
}

class MarkerHandle extends StatefulWidget {
  final bool selected;
  final VoidCallback onSelect;
  final void Function(double) onMove;
  const MarkerHandle({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.onMove,
  });
  @override
  State<MarkerHandle> createState() => _MarkerHandleState();
}

class _MarkerHandleState extends State<MarkerHandle> {
  double dx = 0;
  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: widget.onSelect,
    onPanStart: (_) {
      dx = 0;
      widget.onSelect();
    },
    onPanUpdate: (d) => setState(() => dx += d.delta.dx),
    onPanEnd: (_) {
      widget.onMove(dx);
      setState(() => dx = 0);
    },
    child: Transform.translate(
      offset: Offset(dx, 0),
      child: SizedBox(
        width: 20,
        child: Column(
          children: [
            Icon(
              Icons.flag,
              size: 20,
              color: widget.selected ? Colors.white : accent,
            ),
            Expanded(
              child: Container(width: widget.selected ? 3 : 1, color: accent),
            ),
          ],
        ),
      ),
    ),
  );
}

class TimelinePainter extends CustomPainter {
  final Project p;
  final List<double> peaks;
  final int position;
  final double zoom;
  TimelinePainter(this.p, this.peaks, this.position, this.zoom);
  @override
  void paint(Canvas canvas, Size size) {
    final duration = math.max(1, p.durationUs);
    double x(int time) => time / duration * size.width;
    final pen = Paint()..strokeWidth = 1;
    canvas.drawRect(
      Rect.fromLTRB(0, 24, x(p.startUs), size.height),
      pen..color = Colors.black45,
    );
    canvas.drawRect(
      Rect.fromLTRB(x(p.endUs), 24, size.width, size.height),
      pen..color = Colors.black45,
    );
    final step = math.max(1, (duration / 1000000 / (size.width / 100)).ceil());
    for (var s = 0; s <= duration / 1000000; s += step) {
      final px = x(s * 1000000);
      canvas.drawLine(
        Offset(px, 22),
        Offset(px, size.height),
        pen..color = Colors.white10,
      );
      final text = TextPainter(
        text: TextSpan(
          text: clockTime(s * 1000000).substring(0, 5),
          style: const TextStyle(fontSize: 10, color: Colors.white38),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(canvas, Offset(px + 4, 4));
    }
    final mid = size.height * 0.6;
    if (peaks.isNotEmpty) {
      for (var i = 0; i < peaks.length; i++) {
        final px = i / peaks.length * size.width,
            h = math.max(1, peaks[i] * (size.height - 35) / 2);
        canvas.drawLine(
          Offset(px, mid - h),
          Offset(px, mid + h),
          pen
            ..color = accent.withValues(alpha: 0.65)
            ..strokeWidth = math.max(1, size.width / peaks.length * 0.7),
        );
      }
    }
    for (final s in p.segments) {
      final start = x(p.startUs + (s.startFrame * 1000000 / fps).round());
      final end = x(
        p.startUs + ((s.startFrame + s.frameCount) * 1000000 / fps).round(),
      );
      canvas.drawRect(
        Rect.fromLTRB(start, 25, end, 33),
        pen
          ..color = Colors.primaries[s.imageIndex % Colors.primaries.length]
              .withValues(alpha: 0.8),
      );
    }
    canvas.drawLine(
      Offset(x(position), 20),
      Offset(x(position), size.height),
      pen
        ..strokeWidth = 2
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(TimelinePainter old) => true;
}
