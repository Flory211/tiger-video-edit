import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';
import 'package:media_kit/media_kit.dart';

import 'editor.dart';
import 'model.dart';
import 'platform_media.dart';
import 'media_frames.dart';
import 'v2_panel.dart';
import 'storage.dart';
import 'app_settings.dart';
import 'workspace_shell.dart';
import 'v3_panel.dart';
import 'timeline_tracks.dart';
import 'unsaved.dart';
import 'edit_templates.dart';

Future<void> main(List<String> args, {LocalLibrary? libraryOverride}) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    MediaKit.ensureInitialized();
    final editor = Editor(
      libraryOverride ?? await LocalLibrary.open(),
      AudioEngine(),
    );
    await editor.initialize();
    runApp(
      TigerApp(editor: editor, showHome: true, startInEditor: args.isNotEmpty),
    );
    if (args.isNotEmpty) {
      await editor.guard(() => editor.openProject(args.first));
    }
  } catch (e) {
    if (Platform.isWindows) {
      _windowChannel.setMethodCallHandler(
        (call) async => call.method == 'requestClose',
      );
    }
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

const _windowChannel = MethodChannel('tiger/window');

const accent = Color(0xffc6f36a), panel = Color(0xff191c22);
String labelPath(String? path) =>
    path?.replaceAll('\\', '/').split('/').last ?? 'Музыка не добавлена';
String clockTime(int us) {
  final ms = us ~/ 1000;
  return '${(ms ~/ 60000).toString().padLeft(2, '0')}:${(ms ~/ 1000 % 60).toString().padLeft(2, '0')}.${(ms % 1000).toString().padLeft(3, '0')}';
}

class TigerApp extends StatelessWidget {
  final Editor editor;
  final bool showHome;
  final bool startInEditor;
  const TigerApp({
    super.key,
    required this.editor,
    this.showHome = false,
    this.startInEditor = false,
  });
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AppSettings>(
    valueListenable: editor.settingsNotifier,
    builder: (context, settings, _) => MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Tiger Video Edit',
      theme: _editorTheme(Brightness.light),
      darkTheme: _editorTheme(Brightness.dark),
      themeMode: switch (settings.theme) {
        AppTheme.system => ThemeMode.system,
        AppTheme.dark => ThemeMode.dark,
        AppTheme.light => ThemeMode.light,
      },
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: !settings.animationsAllowed(
            systemReducedMotion: MediaQuery.disableAnimationsOf(context),
          ),
        ),
        child: child!,
      ),
      home: _WindowCloseGuard(
        editor: editor,
        child: showHome
            ? WorkspaceShell(
                editor: editor,
                initialEditor: startInEditor,
                editorBuilder:
                    (context, home, music, sounds, templates, settings) =>
                        EditorScreen(
                          editor: editor,
                          onHome: home,
                          onMusic: music,
                          onSounds: sounds,
                          onTemplates: templates,
                          onSettings: settings,
                        ),
              )
            : EditorScreen(editor: editor),
      ),
    ),
  );
}

ThemeData _editorTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: brightness,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: dark
        ? const Color(0xff101217)
        : const Color(0xfff6f8f1),
    colorScheme: dark
        ? scheme.copyWith(primary: accent, surface: panel)
        : scheme,
    sliderTheme: const SliderThemeData(trackHeight: 3),
    inputDecorationTheme: const InputDecorationTheme(
      isDense: true,
      border: OutlineInputBorder(),
    ),
  );
}

// App-scoped because the initial home screen may not create an EditorScreen.
class _WindowCloseGuard extends StatefulWidget {
  final Editor editor;
  final Widget child;
  const _WindowCloseGuard({required this.editor, required this.child});
  @override
  State<_WindowCloseGuard> createState() => _WindowCloseGuardState();
}

class _WindowCloseGuardState extends State<_WindowCloseGuard> {
  bool checking = false;
  @override
  void initState() {
    super.initState();
    if (Platform.isWindows) _windowChannel.setMethodCallHandler(_request);
  }

  Future<bool> _request(MethodCall call) async {
    if (call.method != 'requestClose') throw MissingPluginException();
    if (checking || !mounted) return false;
    final e = widget.editor;
    if (e.busy || e.exporting) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text(
            'Дождитесь завершения операции или отмените экспорт перед закрытием.',
          ),
        ),
      );
      return false;
    }
    checking = true;
    try {
      return await confirmUnsavedChanges(context, e);
    } finally {
      checking = false;
    }
  }

  @override
  void dispose() {
    if (Platform.isWindows) _windowChannel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class EditorScreen extends StatefulWidget {
  final Editor editor;
  final VoidCallback? onHome, onMusic, onSounds, onTemplates, onSettings;
  const EditorScreen({
    super.key,
    required this.editor,
    this.onHome,
    this.onMusic,
    this.onSounds,
    this.onTemplates,
    this.onSettings,
  });
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
        (e.positionUs - e.project.startUs) * e.project.frameRate ~/ 1000000,
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
    if (!WorkspaceVisibility.isActive(context)) return false;
    if (event is! KeyDownEvent ||
        FocusManager.instance.primaryFocus?.context?.widget is EditableText) {
      return false;
    }
    final focus = FocusManager.instance.primaryFocus;
    if (focus?.context?.findAncestorWidgetOfExactType<EditableText>() != null) {
      return false;
    }
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    if (ctrl && event.logicalKey == LogicalKeyboardKey.keyA) {
      e.selectAllImages();
      return true;
    }
    if (ctrl && event.logicalKey == LogicalKeyboardKey.keyC) {
      e.copyEffects();
      return true;
    }
    if (ctrl && event.logicalKey == LogicalKeyboardKey.keyV) {
      e.pasteEffects();
      return true;
    }
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
    if (!await confirmUnsavedChanges(context, e) || !mounted) return;
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
            child: Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(ctx, controller.text.trim());
              }
            },
            child: Text('Готово'),
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
            title: Text('Найдена автокопия'),
            content: Text(
              'Открыть более новую автоматически сохранённую версию?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Оставить основную'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('Восстановить'),
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
          title: Text('Настройки'),
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
                  title: Text('Отсчёт 3, 2, 1'),
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
                Text(
                  'MP4 • H.264 / AAC • ${e.project.frameRate} FPS\n${e.project.width} × ${e.project.height}',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  'Маркеры действуют только в активном окне. Погрешность нажатия зависит от устройства.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
    await e.guard(e.preferences);
    e.refresh();
  }

  Future<void> relink() async {
    for (final path in e.project.mediaReferences) {
      if (!mounted) return;
      final replace = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(labelPath(path)),
          content: SelectableText(path),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Пропустить'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Указать новый файл'),
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
    if (e.project.musicCredit.isNotEmpty) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Авторство музыки'),
          content: SingleChildScrollView(
            child: SelectableText(
              '${e.project.musicCredit}\n\nИзменения: музыка использована в видеомонтаже.\n\nСохрани эти сведения в описании опубликованного видео или в титрах согласно лицензии.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () => Clipboard.setData(
                ClipboardData(
                  text:
                      '${e.project.musicCredit}\nИзменения: музыка использована в видеомонтаже.',
                ),
              ),
              child: const Text('Копировать'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Экспортировать'),
            ),
          ],
        ),
      );
      if (accepted != true || !mounted) return;
    }
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
        leading: widget.onHome == null
            ? null
            : IconButton(
                tooltip: 'Главное меню',
                onPressed: widget.onHome,
                icon: Icon(Icons.home_outlined),
              ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
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
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          if (!compact)
            Text(
              'Tiger Video Edit',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          IconButton(
            tooltip: 'Сохранить (Ctrl+S)',
            onPressed: locked ? null : () => e.guard(() => e.save()),
            icon: Icon(Icons.save_outlined),
          ),
          IconButton(
            tooltip: 'Настройки',
            onPressed: locked ? null : widget.onSettings ?? settings,
            icon: Icon(Icons.tune),
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
                case 'effects':
                  showEffectLibrary(context, e);
                case 'audioLayer':
                  e.guard(e.importAudioLayer);
                case 'visualLayer':
                  e.addVisualLayer(e.selectedImage);
                case 'sounds':
                  widget.onSounds?.call();
                case 'music':
                  widget.onMusic?.call();
                case 'templates':
                  widget.onTemplates?.call();
                case 'editingSettings':
                  settings();
                case 'autoedit':
                  autoEdit();
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
              const PopupMenuItem(
                value: 'audioLayer',
                child: Text('Добавить аудиодорожку'),
              ),
              const PopupMenuItem(
                value: 'visualLayer',
                child: Text('Добавить медиа в отдельный слой'),
              ),
              const PopupMenuItem(
                value: 'effects',
                child: Text('Библиотека эффектов'),
              ),
              const PopupMenuItem(
                value: 'autoedit',
                child: Text('Auto Edit — стили'),
              ),
              if (widget.onSounds != null)
                const PopupMenuItem(
                  value: 'sounds',
                  child: Text('Библиотека звуков'),
                ),
              if (widget.onMusic != null)
                const PopupMenuItem(
                  value: 'music',
                  child: Text('Музыкальная библиотека'),
                ),
              if (widget.onTemplates != null)
                const PopupMenuItem(
                  value: 'templates',
                  child: Text('Шаблоны эдитов'),
                ),
              const PopupMenuItem(
                value: 'editingSettings',
                child: Text('Настройки монтажа'),
              ),
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
              color: Theme.of(context).colorScheme.errorContainer,
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
                    icon: Icon(Icons.close),
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
                    child: Text('Отменить'),
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
                        SizedBox(
                          width: e.libraryPanelWidth.clamp(
                            180,
                            MediaQuery.sizeOf(context).width * .28,
                          ),
                          child: library(),
                        ),
                        _panelDivider('Медиа', (dx) {
                          e.libraryPanelWidth = (e.libraryPanelWidth + dx)
                              .clamp(
                                180,
                                MediaQuery.sizeOf(context).width * .28,
                              );
                          e.refresh();
                        }),
                        Expanded(child: preview()),
                        _panelDivider('Свойства', (dx) {
                          e.propertiesPanelWidth = (e.propertiesPanelWidth - dx)
                              .clamp(
                                180,
                                MediaQuery.sizeOf(context).width * .28,
                              );
                          e.refresh();
                        }),
                        SizedBox(
                          width: e.propertiesPanelWidth.clamp(
                            180,
                            MediaQuery.sizeOf(context).width * .28,
                          ),
                          child: properties(),
                        ),
                      ],
                    ),
            ),
          ),
          if (e.project.audioClips.isNotEmpty ||
              e.project.visualClips.isNotEmpty ||
              e.project.globalEffects.isNotEmpty)
            AbsorbPointer(
              absorbing: locked,
              child: TimelineTracks(editor: e),
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
          title: Text('Ритм и автосборка'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
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
              child: Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Анализировать'),
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
            child: Text('Оставить текущие'),
          ),
          FilledButton(
            onPressed: count == 0 ? null : () => Navigator.pop(ctx, true),
            child: Text('Автосборка'),
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

  Future<void> autoEdit() async {
    if (e.project.audio == null || e.project.images.isEmpty) {
      e.error = 'Добавьте музыку и медиа для автосборки';
      e.refresh();
      return;
    }
    final profile = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Стиль Auto Edit'),
        children: [
          for (final name in autoEditProfiles)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, name),
              child: Text(name),
            ),
        ],
      ),
    );
    if (profile != null) await e.guard(() => e.applyAutoEdit(profile));
  }

  void showRecent() {
    showDialog<void>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Последние проекты'),
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
      style: TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 13,
        letterSpacing: 1,
      ),
    ),
  );
  Widget _panelDivider(String label, ValueChanged<double> move) => Semantics(
    label: 'Ширина панели $label',
    child: MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        key: ValueKey('resize-$label'),
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) => move(d.delta.dx),
        onHorizontalDragEnd: (_) => e.guard(e.preferences),
        child: SizedBox(
          width: 6,
          child: ColoredBox(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
    ),
  );

  Widget library() => Material(
    color: Theme.of(context).colorScheme.surface,
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
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'Порядок = порядок смены\nПеретащите строку за ручку',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
        ),
        Expanded(
          child: e.project.images.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.photo_library_outlined,
                        size: 40,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Ваши кадры — ваш ритм',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      TextButton(
                        onPressed: showRecent,
                        child: Text('Последние проекты'),
                      ),
                    ],
                  ),
                )
              : ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  itemCount: e.project.images.length,
                  onReorderItem: (oldIndex, newIndex) => e.reorder(
                    oldIndex,
                    newIndex > oldIndex ? newIndex + 1 : newIndex,
                  ),
                  itemBuilder: (ctx, i) {
                    final s = e.project.images[i];
                    return ListTile(
                      key: ValueKey('$i:${s.path}'),
                      trailing: ReorderableDragStartListener(
                        index: i,
                        child: const Padding(
                          padding: EdgeInsets.all(12),
                          child: Icon(Icons.drag_handle, size: 20),
                        ),
                      ),
                      selected:
                          e.selectedImages.contains(i) || e.selectedImage == i,
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
                                    Icon(Icons.broken_image),
                              ),
                      ),
                      title: Text(
                        labelPath(s.path),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11),
                      ),
                      subtitle: Text(
                        '${i + 1}'.padLeft(2, '0'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      onTap: () {
                        e.selectImage(
                          i,
                          additive: HardwareKeyboard.instance.isControlPressed,
                        );
                        e.selectedMarker = null;
                        e.refresh();
                      },
                      onLongPress: () => e.selectImage(i, additive: true),
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
            icon: Icon(Icons.delete_outline, size: 16),
            label: Text('Удалить выбранное'),
          ),
      ],
    ),
  );
  Widget preview() {
    final active = e.project.imageIndexAt(e.positionUs);
    final localFrame = math.max(
      0,
      (e.positionUs - e.project.startUs) * e.project.frameRate ~/ 1000000 -
          (e.project.segmentAt(e.positionUs)?.startFrame ?? 0),
    );
    final previewLocalUs =
        (localFrame * 1000000 + e.project.frameRate - 1) ~/ e.project.frameRate;
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
              Icon(
                Icons.crop_free,
                size: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                'ПРЕДПРОСМОТР',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                                maxDimension:
                                    switch (e.settings.previewQuality) {
                                      PreviewQuality.low => 640,
                                      PreviewQuality.medium => 1280,
                                      PreviewQuality.high => 1920,
                                    },
                                localUs: e.inspectImage && !e.playing
                                    ? 0
                                    : previewLocalUs,
                              )
                            else
                              Center(
                                child: Text(
                                  'Добавьте музыку и изображения',
                                  style: TextStyle(color: Colors.white60),
                                ),
                              ),
                            if (e.countdownValue > 0)
                              Center(
                                child: Text(
                                  '${e.countdownValue}',
                                  style: TextStyle(
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
            style: TextStyle(
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
                icon: Icon(Icons.skip_previous),
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
                icon: Icon(Icons.flag_outlined),
                label: Text('Маркер ${e.markerKey}'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Space — воспроизведение • два нажатия на шкале — маркер',
            style: TextStyle(
              fontSize: 10,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
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
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'СВОЙСТВА',
            style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 1),
          ),
          const SizedBox(height: 18),
          if (selected != null) ...[
            Text('Выбранный маркер', style: TextStyle(color: accent)),
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
              child: Text('Снять выбор'),
            ),
            const Divider(),
          ],
          if (still != null) ...[
            Text(
              'Изображение ${e.selectedImage + 1}',
              style: TextStyle(color: accent),
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
              onPressed: () =>
                  e.updateStill(still.copy(scale: 1, x: 0, y: 0, cover: true)),
              child: Text('Сбросить положение'),
            ),
            const Divider(),
          ],
          V2Panel(editor: e),
          const Divider(),
          V3Panel(editor: e),
          const Divider(),
          Text(
            'Музыкальный отрывок',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
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
            '${e.project.width} × ${e.project.height}\n${e.project.frameRate} FPS • H.264 / AAC',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget timeline(bool compact) {
    final p = e.project;
    return Container(
      height: compact ? 210 : 240,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        border: Border(
          top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
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
                  icon: Icon(Icons.undo, size: 18),
                ),
                IconButton(
                  tooltip: 'Вернуть',
                  onPressed: e.history.canRedo ? () => e.guard(e.redo) : null,
                  icon: Icon(Icons.redo, size: 18),
                ),
                Expanded(
                  child: Text(
                    labelPath(p.audio),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                IconButton(
                  tooltip: 'Ритм и автосборка',
                  onPressed: p.audio == null ? null : beats,
                  icon: Icon(Icons.auto_awesome, size: 20),
                ),
                IconButton(
                  tooltip: 'Импорт музыки',
                  onPressed: () => e.guard(e.importAudio),
                  icon: Icon(Icons.audio_file_outlined, size: 20),
                ),
                if (!compact)
                  Text(
                    '${p.markers.length} маркеров',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                Icon(Icons.zoom_in, size: 18),
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
                                foreground: Theme.of(context)
                                    .colorScheme
                                    .onSurface,
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
                                  e.snapTime(
                                    at(m.timeUs / duration * width + dx),
                                    excludeMarkerId: m.id,
                                  ),
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
                Icon(Icons.graphic_eq, size: 12, color: accent),
                const SizedBox(width: 8),
                Text(
                  '${clockTime(p.startUs)} — ${clockTime(p.endUs)}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 10,
                  ),
                ),
                const Spacer(),
                Text(
                  '${e.zoom.toStringAsFixed(1)}×',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 10,
                  ),
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
  final int localUs, sourceUs, maxDimension;
  const StillView({
    super.key,
    required this.still,
    required this.project,
    this.localUs = 0,
    this.sourceUs = 0,
    this.maxDimension = 1280,
  });
  @override
  State<StillView> createState() => _StillViewState();
}

class _StillViewState extends State<StillView> {
  ui.Image? image;
  String? error, compositionError;
  bool loading = false;
  int displayedFrame = -1;
  int displayedStart = -1;
  String? displayedPath;
  late MediaFrameSource source;
  late MediaFrameSource _previousSource;
  int _decoderEpoch = 0;
  final _overlaySources = <String, MediaFrameSource>{};
  ui.Image? _previousImage;
  Still? _previousItem;
  String _previousKey = '';
  List<VisualFrame> _overlays = [];
  bool _compositionLoading = false;
  int _compositionFrame = -1;
  Project? _compositionProject;
  @override
  void initState() {
    super.initState();
    source = MediaFrameSource(maxDimension: widget.maxDimension);
    _previousSource = MediaFrameSource(maxDimension: widget.maxDimension);
    load();
    loadComposition();
  }

  @override
  void didUpdateWidget(StillView old) {
    super.didUpdateWidget(old);
    final qualityChanged = old.maxDimension != widget.maxDimension;
    if (qualityChanged) {
      _decoderEpoch++;
      error = null;
      compositionError = null;
      unawaited(source.dispose());
      unawaited(_previousSource.dispose());
      for (final decoder in _overlaySources.values) {
        unawaited(decoder.dispose());
      }
      _overlaySources.clear();
      source = MediaFrameSource(maxDimension: widget.maxDimension);
      _previousSource = MediaFrameSource(maxDimension: widget.maxDimension);
      _previousKey = '';
      _compositionProject = null;
      _compositionFrame = -1;
    }
    if (qualityChanged ||
        old.project.frameRate != widget.project.frameRate ||
        old.still.path != widget.still.path ||
        old.still.sourceStartUs != widget.still.sourceStartUs ||
        (widget.still.kind != 'image' &&
            old.localUs * old.project.frameRate ~/ 1000000 !=
                widget.localUs * widget.project.frameRate ~/ 1000000)) {
      load();
    }
    loadComposition();
  }

  Future<void> loadComposition() async {
    final p = widget.project, epoch = _decoderEpoch;
    final frame = math.max(
      0,
      (widget.sourceUs - p.startUs) * p.frameRate ~/ 1000000,
    );
    final time = p.startUs + (frame * 1000000 + p.frameRate - 1) ~/ p.frameRate;
    if (_compositionLoading ||
        (_compositionFrame == frame && identical(_compositionProject, p))) {
      return;
    }
    _compositionLoading = true;
    final previousSource = _previousSource, frames = <VisualFrame>[];
    ui.Image? nextPrevious;
    Still? nextPreviousItem;
    var nextKey = '';
    var ownsPrevious = false, committed = false;
    try {
      final schedule = p.segments;
      final current = schedule.lastIndexWhere((s) => s.startFrame <= frame);
      final needPrevious =
          widget.still.effectStack.any(
            (e) => ['crossfade', 'slide', 'wipe'].contains(e.type),
          ) ||
          p.globalEffects.any(
            (l) => l.effects.any(
              (e) => ['crossfade', 'slide', 'wipe'].contains(e.type),
            ),
          );
      if (needPrevious && current > 0) {
        final prev = schedule[current - 1], item = p.images[prev.imageIndex];
        nextKey = [item.path, item.sourceStartUs, prev.startFrame].join(':');
        nextPreviousItem = item;
        if (nextKey == _previousKey) {
          nextPrevious = _previousImage;
        } else {
          nextPrevious = await previousSource.frame(
            item,
            (prev.frameCount - 1) * 1000000 ~/ p.frameRate,
          );
          ownsPrevious = true;
        }
      }
      if (!mounted || epoch != _decoderEpoch) return;
      final active = p.visualClips.where((c) => c.activeAt(time)).toList()
        ..sort((a, b) => a.track.compareTo(b.track));
      for (final clip in active) {
        if (epoch != _decoderEpoch) return;
        final decoder = _overlaySources.putIfAbsent(
          clip.id,
          () => MediaFrameSource(maxDimension: widget.maxDimension),
        );
        final decoded = await decoder.frame(clip.media, time - clip.startUs);
        frames.add(
          VisualFrame(clip.media, decoded, time - clip.startUs, clip.opacity),
        );
      }
      if (!mounted || epoch != _decoderEpoch || !identical(widget.project, p)) {
        return;
      }
      final oldFrames = _overlays, oldPrevious = _previousImage;
      setState(() {
        _previousImage = nextPrevious;
        _previousItem = nextPreviousItem;
        _previousKey = nextKey;
        _overlays = frames;
        _compositionFrame = frame;
        _compositionProject = p;
        compositionError = null;
      });
      committed = true;
      if (oldPrevious != nextPrevious) oldPrevious?.dispose();
      for (final f in oldFrames) {
        f.image.dispose();
      }
      for (final id
          in _overlaySources.keys
              .where((id) => !active.any((c) => c.id == id))
              .toList()) {
        await _overlaySources.remove(id)!.dispose();
      }
    } catch (err) {
      if (mounted && epoch == _decoderEpoch && identical(widget.project, p)) {
        setState(() => compositionError = 'Слой: $err');
      }
    } finally {
      if (!committed) {
        for (final f in frames) {
          f.image.dispose();
        }
        if (ownsPrevious) nextPrevious?.dispose();
      }
      _compositionLoading = false;
      if (mounted) {
        final latest = widget.project,
            latestFrame = math.max(
              0,
              (widget.sourceUs - widget.project.startUs) *
                  widget.project.frameRate ~/
                  1000000,
            );
        if ((_compositionFrame != latestFrame ||
                !identical(_compositionProject, latest)) &&
            (compositionError == null ||
                epoch != _decoderEpoch ||
                !identical(latest, p) ||
                latestFrame != frame)) {
          unawaited(loadComposition());
        }
      }
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
    final epoch = _decoderEpoch,
        decoder = source,
        frameRate = widget.project.frameRate;
    final item = widget.still, time = widget.localUs;
    try {
      final decoded = item.kind == 'image'
          ? (await previewImages.load(item.path)).clone()
          : await decoder.frame(item, time);
      if (!mounted ||
          epoch != _decoderEpoch ||
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
        displayedFrame = time * frameRate ~/ 1000000;
        error = null;
      });
      old?.dispose();
    } catch (e) {
      if (mounted &&
          epoch == _decoderEpoch &&
          widget.still.path == item.path &&
          widget.still.sourceStartUs == item.sourceStartUs) {
        setState(() => error = e.toString());
      }
    } finally {
      loading = false;
      if (mounted &&
          (epoch != _decoderEpoch ||
              widget.still.path != item.path ||
              widget.still.sourceStartUs != item.sourceStartUs ||
              (widget.still.kind != 'image' &&
                  displayedFrame !=
                      widget.localUs * widget.project.frameRate ~/ 1000000 &&
                  error == null))) {
        load();
      }
    }
  }

  @override
  void dispose() {
    image?.dispose();
    source.dispose();
    _previousImage?.dispose();
    _previousSource.dispose();
    for (final frame in _overlays) {
      frame.image.dispose();
    }
    for (final decoder in _overlaySources.values) {
      decoder.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => (error ?? compositionError) != null
      ? Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Медиа недоступно: ${error ?? compositionError}',
              maxLines: 5,
            ),
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
            previousImage: _previousImage,
            previousItem: _previousItem,
            overlays: _overlays,
          ),
        );
}

class StillPainter extends CustomPainter {
  final ui.Image image;
  final Still still;
  final Project project;
  final int localUs, sourceUs;
  final ui.Image? previousImage;
  final Still? previousItem;
  final List<VisualFrame> overlays;
  StillPainter(
    this.image,
    this.still,
    this.project,
    this.localUs,
    this.sourceUs, {
    this.previousImage,
    this.previousItem,
    this.overlays = const [],
  });
  @override
  void paint(Canvas canvas, Size size) => paintFrame(
    canvas,
    size,
    image,
    still,
    localUs: localUs,
    sourceUs:
        project.startUs +
        ((sourceUs - project.startUs) * project.frameRate ~/ 1000000) *
            1000000 ~/
            project.frameRate,
    captions: project.captions,
    referenceWidth: project.width.toDouble(),
    project: project,
    previousImage: previousImage,
    previousItem: previousItem,
    overlays: overlays,
  );
  @override
  bool shouldRepaint(StillPainter old) =>
      old.image != image ||
      old.still != still ||
      old.localUs != localUs ||
      old.sourceUs != sourceUs ||
      old.project != project ||
      old.previousImage != previousImage ||
      old.previousItem != previousItem ||
      !listEquals(old.overlays, overlays);
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
              color: widget.selected
                  ? Theme.of(context).colorScheme.onSurface
                  : Theme.of(context).colorScheme.primary,
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
  final Color foreground;
  TimelinePainter(
    this.p,
    this.peaks,
    this.position,
    this.zoom, {
    this.foreground = Colors.white,
  });
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
        pen..color = foreground.withValues(alpha: .1),
      );
      final text = TextPainter(
        text: TextSpan(
          text: clockTime(s * 1000000).substring(0, 5),
          style: TextStyle(
            fontSize: 10,
            color: foreground.withValues(alpha: .6),
          ),
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
      final start = x(
        p.startUs + (s.startFrame * 1000000 / p.frameRate).round(),
      );
      final end = x(
        p.startUs +
            ((s.startFrame + s.frameCount) * 1000000 / p.frameRate).round(),
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
        ..color = foreground,
    );
  }

  @override
  bool shouldRepaint(TimelinePainter old) => true;
}
