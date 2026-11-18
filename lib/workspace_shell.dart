import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_info.dart';
import 'dashboard.dart';
import 'editor.dart';
import 'media_bridge.dart';
import 'music_library.dart';
import 'service_pages.dart';
import 'sound_library.dart';
import 'template_page.dart';
import 'unsaved.dart';
import 'update_service.dart';

typedef EditorWorkspaceBuilder = Widget Function(
  BuildContext context,
  VoidCallback onHome,
  VoidCallback onMusic,
  VoidCallback onSounds,
  VoidCallback onTemplates,
  VoidCallback onSettings,
);

/// Also gates global hardware-keyboard handlers while the retained editor is
/// hidden behind the dashboard or a service page.
class WorkspaceVisibility extends InheritedWidget {
  final bool active;
  const WorkspaceVisibility({
    super.key,
    required this.active,
    required super.child,
  });
  static bool isActive(BuildContext context) =>
      context.getInheritedWidgetOfExactType<WorkspaceVisibility>()?.active ??
      true;
  @override
  bool updateShouldNotify(WorkspaceVisibility oldWidget) =>
      active != oldWidget.active;
}

class WorkspaceShell extends StatefulWidget {
  final Editor editor;
  final EditorWorkspaceBuilder editorBuilder;
  final UpdateService? updateService;
  final bool initialEditor;
  const WorkspaceShell({
    super.key,
    required this.editor,
    required this.editorBuilder,
    this.updateService,
    this.initialEditor = false,
  });
  @override
  State<WorkspaceShell> createState() => _WorkspaceShellState();
}

class _WorkspaceShellState extends State<WorkspaceShell> {
  Editor get editor => widget.editor;
  late final MusicLibrary music = MusicLibrary(
    Directory('${editor.library.root.path}/music'),
  );
  late final SoundLibrary sounds = SoundLibrary(
    Directory('${editor.library.root.path}/sounds'),
  );
  late final UpdateService updates =
      widget.updateService ??
      UpdateService(
        owner: const String.fromEnvironment(
          'TVE_GITHUB_OWNER',
          defaultValue: 'Flory211',
        ),
        repository: const String.fromEnvironment(
          'TVE_GITHUB_REPO',
          defaultValue: 'tiger-video-edit',
        ),
        cacheFile: File('${editor.library.root.path}/updates.json'),
      );
  bool editorVisible = false,
      working = false,
      routeOpen = false,
      sessionStarted = false;
  Widget? retainedEditor;
  Object? _lastSettings;
  String _lastSummary = '';
  UpdateCheck? pendingUpdateNotice;
  bool get hasSession =>
      sessionStarted ||
      editor.projectPath != null ||
      editor.project.audio != null ||
      editor.project.images.isNotEmpty ||
      editor.dirty ||
      editorVisible;
  String? get lastPath => editor.projectPath ?? editor.recent.firstOrNull;

  @override
  void initState() {
    super.initState();
    editorVisible = widget.initialEditor;
    sessionStarted = widget.initialEditor;
    _lastSettings = editor.settings;
    _lastSummary = _summary();
    editor.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_automaticUpdate());
    });
  }

  String _summary() =>
      '${editor.projectPath}|${editor.project.name}|${editor.dirty}|${editor.recent.join('|')}';
  void _changed() {
    final summary = _summary();
    if (summary == _lastSummary && identical(_lastSettings, editor.settings)) {
      return;
    }
    _lastSummary = summary;
    _lastSettings = editor.settings;
    if (mounted) setState(() {});
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (working) return;
    setState(() => working = true);
    try {
      await operation();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) {
        setState(() => working = false);
        _notifyUpdate();
      }
    }
  }

  bool _mayReplace() {
    if (!editor.busy && !editor.exporting) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Дождись завершения текущей операции.')),
    );
    return false;
  }

  void _newProject() => unawaited(
    _run(() async {
      if (!_mayReplace() ||
          !await confirmUnsavedChanges(context, editor) ||
          !mounted) {
        return;
      }
      await editor.newProject('Новый проект');
      if (mounted) {
        setState(() {
          editorVisible = true;
          sessionStarted = true;
        });
      }
    }),
  );
  void _home() => unawaited(
    _run(() async {
      if (!await confirmUnsavedChanges(
            context,
            editor,
            preserveSession: true,
          ) ||
          !mounted) {
        return;
      }
      await editor.stop();
      if (mounted) setState(() => editorVisible = false);
    }),
  );
  void _continue() => unawaited(
    _run(() async {
      if (hasSession) {
        setState(() => editorVisible = true);
        return;
      }
      final path = lastPath;
      if (path != null) await _openProject(path);
    }),
  );
  Future<bool> _openProject(String path) async {
    if (!_mayReplace() ||
        !await confirmUnsavedChanges(context, editor) ||
        !mounted) {
      return false;
    }
    await editor.openProject(path);
    if (mounted) {
      setState(() {
        editorVisible = true;
        sessionStarted = true;
      });
    }
    return true;
  }

  Future<void> _page(Widget page) async {
    await editor.stop();
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    setState(() => routeOpen = true);
    try {
      await Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => page));
    } finally {
      if (mounted) setState(() => routeOpen = false);
    }
  }

  void _music() => unawaited(
    _run(
      () => _page(
        MusicLibraryPage(
          library: music,
          previewVolume: editor.settings.previewVolume,
          onUse: (track) async {
            if (!_mayReplace()) throw StateError('Редактор занят');
            await editor.useAudioPath(
              track.path,
              musicCredit: track.license.attribution,
            );
            if (mounted) {
              setState(() {
                editorVisible = true;
                sessionStarted = true;
              });
              Navigator.of(context).popUntil((route) => route.isFirst);
            }
          },
        ),
      ),
    ),
  );
  void _sounds() => unawaited(
    _run(
      () => _page(
        SoundLibraryPage(
          library: sounds,
          previewVolume: editor.settings.previewVolume,
          onAdd: (sound, atMarkers) {
            if (!_mayReplace()) throw StateError('Редактор занят');
            editor.addSound(sound, atMarkers: atMarkers);
            if (mounted) {
              setState(() => editorVisible = true);
              Navigator.of(context).pop();
            }
          },
        ),
      ),
    ),
  );
  void _settings() => unawaited(
    _run(
      () => _page(
        SettingsPage(
          settings: editor.settings,
          onChanged: editor.updateSettings,
        ),
      ),
    ),
  );
  void _templates() => unawaited(
    _run(() async {
      final before = editor.project, pending = editor.pendingTemplate;
      await _page(TemplatesPage(editor: editor));
      if (mounted &&
          (!identical(before, editor.project) ||
              !identical(pending, editor.pendingTemplate))) {
        setState(() {
          editorVisible = true;
          sessionStarted = true;
        });
      }
    }),
  );
  void _projects() => unawaited(
    _run(
      () => _page(
        ProjectsPage(
          root: editor.library.root,
          recent: editor.recent,
          onOpen: (path) async {
            final opened = await _openProject(path);
            if (mounted && opened) Navigator.of(context).pop();
          },
        ),
      ),
    ),
  );
  void _updates() => unawaited(
    _run(
      () => _page(
        UpdatesPage(
          service: updates,
          currentVersion: appVersion,
          downloadDirectory: Directory('${editor.library.root.path}/updates'),
          onOpenDownloaded: _openInstaller,
        ),
      ),
    ),
  );

  Future<void> _openInstaller(File file) async {
    if (!await file.exists()) {
      throw const FileSystemException('Скачанный установщик не найден');
    }
    if (Platform.isWindows) {
      await Process.start(file.path, const [], mode: ProcessStartMode.normal);
    } else if (Platform.isAndroid) {
      final status = await nativeMedia.invokeMethod<String>('installUpdate', {
        'path': file.absolute.path,
      });
      if (status == 'permission-required' && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Разреши установку из этого источника в системных настройках, '
              'затем вернись и снова нажми «Открыть системный установщик».',
            ),
          ),
        );
      }
    } else {
      throw UnsupportedError('Установка доступна на Windows и Android');
    }
  }

  Future<void> _automaticUpdate() async {
    if (!editor.settings.autoCheckUpdates) return;
    final result = await updates.check(
      currentVersion: appVersion,
      platform: Platform.isAndroid
          ? UpdatePlatform.androidArm64
          : UpdatePlatform.windowsX64,
    );
    if (!mounted ||
        !editor.settings.updateNotifications ||
        result.status != UpdateStatus.available) {
      return;
    }
    pendingUpdateNotice = result;
    _notifyUpdate();
  }

  void _notifyUpdate() {
    if (!editor.settings.updateNotifications) {
      pendingUpdateNotice = null;
      return;
    }
    final result = pendingUpdateNotice;
    if (!mounted || result == null || working || routeOpen) return;
    pendingUpdateNotice = null;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Доступна новая версия Tiger Video Edit ${result.release!.version}',
        ),
        action: SnackBarAction(label: 'Подробнее', onPressed: _updates),
      ),
    );
  }

  @override
  void dispose() {
    editor.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    retainedEditor ??= widget.editorBuilder(
      context,
      _home,
      _music,
      _sounds,
      _templates,
      _settings,
    );
    final reduceMotion = !editor.settings.animationsAllowed(
      systemReducedMotion: MediaQuery.disableAnimationsOf(context),
    );
    final dashboard = TigerDashboard(
      onCreate: _newProject,
      onProjects: _projects,
      onTemplates: _templates,
      onMusic: _music,
      onSounds: _sounds,
      onUpdates: _updates,
      onSettings: _settings,
      onContinue: hasSession || lastPath != null ? _continue : null,
      lastProject: hasSession
          ? editor.project.name
          : lastPath?.replaceAll('\\', '/').split('/').last,
      reduceMotion: reduceMotion,
    );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || working || ModalRoute.of(context)?.isCurrent != true) {
          return;
        }
        if (editorVisible) {
          _home();
        } else if (Platform.isAndroid) {
          unawaited(
            _run(() async {
              if (!_mayReplace() ||
                  !await confirmUnsavedChanges(context, editor)) {
                return;
              }
              await SystemNavigator.pop();
            }),
          );
        }
      },
      child: Stack(
        children: [
          IndexedStack(
            index: editorVisible ? 1 : 0,
            children: [
              dashboard,
              WorkspaceVisibility(
                active: editorVisible && !routeOpen && !working,
                child: TickerMode(
                  enabled: editorVisible && !routeOpen,
                  child: retainedEditor!,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<List<String>> discoverProjects(
  Directory root,
  List<String> recent,
) async {
  String canonical(String path) =>
      File(path).absolute.uri
          .normalizePath()
          .toFilePath(windows: Platform.isWindows);
  String key(String path) => Platform.isWindows ? path.toLowerCase() : path;
  final paths = <String, String>{};
  final recentKeys = recent.map((path) => key(canonical(path))).toList();
  for (final path in recent) {
    if (await File(path).exists()) {
      final normalized = canonical(path);
      paths.putIfAbsent(key(normalized), () => normalized);
    }
  }
  final directory = Directory('${root.path}/projects');
  if (await directory.exists()) {
    await for (final entry in directory.list(followLinks: false)) {
      if (entry is File &&
          RegExp(r'\.(tve|leos)$', caseSensitive: false).hasMatch(entry.path)) {
        final normalized = canonical(entry.path);
        paths.putIfAbsent(key(normalized), () => normalized);
      }
    }
  }
  final result = paths.values.toList();
  result.sort((a, b) {
    final ai = recentKeys.indexOf(key(a)), bi = recentKeys.indexOf(key(b));
    if (ai >= 0 || bi >= 0) {
      return ai < 0
          ? 1
          : bi < 0
          ? -1
          : ai.compareTo(bi);
    }
    return a.toLowerCase().compareTo(b.toLowerCase());
  });
  return result;
}

class ProjectsPage extends StatefulWidget {
  final Directory root;
  final List<String> recent;
  final Future<void> Function(String path) onOpen;
  const ProjectsPage({
    super.key,
    required this.root,
    required this.recent,
    required this.onOpen,
  });
  @override
  State<ProjectsPage> createState() => _ProjectsPageState();
}

class _ProjectsPageState extends State<ProjectsPage> {
  late Future<List<String>> paths = discoverProjects(
    widget.root,
    widget.recent,
  );
  String query = '';
  bool opening = false;
  Future<void> _open(String path) async {
    if (opening) return;
    setState(() => opening = true);
    try {
      await widget.onOpen(path);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось открыть проект: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => opening = false);
    }
  }

  Future<void> _pick() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: 'Tiger Video Edit',
            extensions: ['tve', 'leos'],
          ),
        ],
      );
      if (file != null) await _open(file.path);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Мои проекты'),
      actions: [
        IconButton(
          tooltip: 'Обновить список',
          onPressed: () => setState(
            () => paths = discoverProjects(widget.root, widget.recent),
          ),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Поиск проектов',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) => setState(() => query = value),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: opening ? null : _pick,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Открыть файл .tve / .leos'),
                ),
              ),
            ],
          ),
        ),
        if (opening) const LinearProgressIndicator(),
        Expanded(
          child: FutureBuilder<List<String>>(
            future: paths,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: SelectableText(
                    'Не удалось прочитать список проектов: ${snapshot.error}',
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final visible = snapshot.data!
                  .where((p) => p.toLowerCase().contains(query.toLowerCase()))
                  .toList();
              if (visible.isEmpty) {
                return const Center(
                  child: Text(
                    'Проекты не найдены. Открой .tve или создай новый проект.',
                  ),
                );
              }
              return ListView.builder(
                itemCount: visible.length,
                itemBuilder: (context, index) {
                  final path = visible[index];
                  return ListTile(
                    leading: const Icon(Icons.movie_outlined),
                    title: Text(path.replaceAll('\\', '/').split('/').last),
                    subtitle: Text(
                      path,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: opening ? null : () => _open(path),
                  );
                },
              );
            },
          ),
        ),
      ],
    ),
  );
}
