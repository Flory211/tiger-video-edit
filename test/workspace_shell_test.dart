import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiger_video_edit/app_settings.dart';
import 'package:tiger_video_edit/editor.dart';
import 'package:tiger_video_edit/model.dart';
import 'package:tiger_video_edit/storage.dart';
import 'package:tiger_video_edit/workspace_shell.dart';

class ShellEditor extends Fake implements Editor {
  final LocalLibrary local;
  ShellEditor(Directory directory) : local = LocalLibrary(directory);
  @override
  LocalLibrary get library => local;
  @override
  AppSettings get settings => const AppSettings(autoCheckUpdates: false);
  @override
  Project project = Project();
  @override
  String? projectPath;
  @override
  List<String> recent = [];
  @override
  bool dirty = false;
  @override
  bool busy = false;
  @override
  bool exporting = false;
  final listeners = <VoidCallback>[];
  int created = 0;
  int saves = 0;
  bool saveClearsDirty = false;
  @override
  void addListener(VoidCallback listener) => listeners.add(listener);
  @override
  void removeListener(VoidCallback listener) => listeners.remove(listener);
  @override
  Future<void> stop() async {}
  @override
  Future<void> save({bool autosave = false, bool saveAs = false}) async {
    saves++;
    if (saveClearsDirty) dirty = false;
  }

  @override
  Future<void> newProject(String name) async {
    created++;
    dirty = false;
  }
}

void main() {
  late Directory directory;
  late ShellEditor editor;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('tve-shell-test-');
    editor = ShellEditor(directory);
  });
  tearDown(() => directory.deleteSync(recursive: true));
  Widget app() => MaterialApp(
    home: WorkspaceShell(
      editor: editor,
      editorBuilder: (context, home, music, sounds, templates, settings) =>
          Scaffold(
            body: Column(
              children: [
                const Text('Editor sentinel'),
                TextButton(onPressed: home, child: const Text('Go home')),
              ],
            ),
          ),
    ),
  );
  testWidgets(
    'new project reveals permanent editor and home keeps it mounted',
    (tester) async {
      await tester.pumpWidget(app());
      expect(find.text('Editor sentinel'), findsNothing);
      await tester.tap(find.text('Новый проект').first);
      await tester.pumpAndSettle();
      expect(editor.created, 1);
      expect(find.text('Editor sentinel'), findsOneWidget);
      await tester.tap(find.text('Go home'));
      await tester.pumpAndSettle();
      expect(find.text('Новый проект'), findsWidgets);
      expect(find.text('Editor sentinel', skipOffstage: false), findsOneWidget);
    },
  );
  testWidgets('canceling dirty new project preserves existing work', (
    tester,
  ) async {
    editor.dirty = true;
    await tester.pumpWidget(app());
    await tester.tap(find.text('Новый проект').first);
    await tester.pumpAndSettle();
    expect(find.text('Несохранённые изменения'), findsOneWidget);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(editor.created, 0);
    expect(editor.dirty, true);
  });
  testWidgets('settings route is usable on phone', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app());
    await tester.ensureVisible(find.text('Настройки'));
    await tester.tap(find.text('Настройки'));
    await tester.pumpAndSettle();
    expect(find.text('Уменьшить анимации'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('cancelled save cannot replace dirty project', (tester) async {
    editor.dirty = true;
    await tester.pumpWidget(app());
    await tester.tap(find.text('Новый проект').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(editor.saves, 1);
    expect(editor.created, 0);
    expect(editor.dirty, true);
  });
  testWidgets('home retains unsaved session and continue returns to it', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.tap(find.text('Новый проект').first);
    await tester.pumpAndSettle();
    editor.dirty = true;
    await tester.tap(find.text('Go home'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Оставить несохранённым'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Продолжить проект'));
    await tester.pumpAndSettle();
    expect(find.text('Editor sentinel'), findsOneWidget);
    expect(editor.dirty, true);
    expect(editor.created, 1);
  });
  test('local project discovery combines recent and library files without unrelated files', () async {
    final projects = Directory('${directory.path}/projects')..createSync();
    final first = File('${projects.path}/first.tve')..writeAsStringSync('{}');
    final second = File('${projects.path}/second.leos')
      ..writeAsStringSync('{}');
    File('${projects.path}/not-a-project.mp3').writeAsStringSync('audio');
    final discovered = await discoverProjects(directory, [
      second.path,
      '${directory.path}/missing.tve',
    ]);
    expect(discovered.map((p) => p.replaceAll('\\', '/')).toList(), [
      second.path.replaceAll('\\', '/'),
      first.path.replaceAll('\\', '/'),
    ]);
  });
}
