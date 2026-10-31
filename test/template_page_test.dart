import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiger_video_edit/editor.dart';
import 'package:tiger_video_edit/model.dart';
import 'package:tiger_video_edit/storage.dart';
import 'package:tiger_video_edit/edit_templates.dart';
import 'package:tiger_video_edit/template_page.dart';

class TemplateEditor extends ChangeNotifier implements Editor {
  TemplateEditor(Directory root) : library = LocalLibrary(root);
  @override
  final LocalLibrary library;
  @override
  Project project = Project(
    images: [
      const Still(
        path: 'x',
        effectStack: [EffectInstance(id: 'e', type: 'zoom')],
      ),
    ],
  );
  @override
  int selectedImage = 0;
  @override
  EditTemplate? pendingTemplate;
  @override
  Future<void> applyTemplate(EditTemplate t) async {
    pendingTemplate = t;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await Future<void>.delayed(const Duration(milliseconds: 30));
  await tester.pumpAndSettle();
}

Future<void> idle(WidgetTester tester) async {
  for (var i = 0; i < 100; i++) {
    await tester.pump();
    if (find.text('Обработка…').evaluate().isEmpty) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Template storage operation did not finish');
}

void main() {
  testWidgets(
    'duplicate creates own template; rename and delete preserve builtins',
    (tester) async {
      await tester.runAsync(() async {
        final dir = await Directory.systemTemp.createTemp(
          'tiger-template-edit',
        );
        addTearDown(() => dir.delete(recursive: true));
        final e = TemplateEditor(dir),
            store = TemplateStore(
              Directory.fromUri(dir.uri.resolve('templates/')),
            );
        await tester.pumpWidget(
          MaterialApp(
            home: TemplatesPage(editor: e, store: store),
          ),
        );
        await settle(tester);
        await tester.tap(find.byTooltip('Действия: Smooth'));
        await settle(tester);
        expect(find.text('Переименовать'), findsNothing);
        expect(find.text('Удалить'), findsNothing);
        await tester.tap(find.text('Дублировать'));
        await settle(tester);
        await idle(tester);
        expect((await store.load()).single.name, 'Smooth — копия');
        await tester.enterText(
          find.widgetWithText(TextField, 'Поиск шаблона'),
          'копия',
        );
        await settle(tester);
        await tester.tap(find.byTooltip('Действия: Smooth — копия'));
        await settle(tester);
        await tester.tap(find.text('Переименовать'));
        await settle(tester);
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Название'),
          'Переименован',
        );
        await tester.tap(find.text('Сохранить'));
        await settle(tester);
        await idle(tester);
        expect((await store.load()).single.name, 'Переименован');
        await tester.enterText(
          find.widgetWithText(TextField, 'Поиск шаблона'),
          'Переименован',
        );
        await settle(tester);
        await tester.tap(find.byTooltip('Действия: Переименован'));
        await settle(tester);
        await tester.tap(find.text('Удалить'));
        await settle(tester);
        await tester.tap(find.text('Удалить'));
        await settle(tester);
        await idle(tester);
        expect(await store.load(), isEmpty);
        expect(builtinEditTemplates.first.name, 'Smooth');
        expect(tester.takeException(), isNull);
      });
    },
  );
  testWidgets(
    'applying template before media sets pending template and returns to editor',
    (tester) async {
      await tester.runAsync(() async {
        final dir = await Directory.systemTemp.createTemp(
          'tiger-template-apply',
        );
        addTearDown(() => dir.delete(recursive: true));
        final e = TemplateEditor(dir),
            store = TemplateStore(
              Directory.fromUri(dir.uri.resolve('templates/')),
            );
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => TemplatesPage(editor: e, store: store),
                    ),
                  ),
                  child: const Text('Открыть шаблоны'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Открыть шаблоны'));
        await settle(tester);
        expect(
          find.text(
            'Выберите шаблон сейчас: он применится после добавления музыки и изображений.',
          ),
          findsOneWidget,
        );
        await idle(tester);
        await tester.tap(find.text('Smooth'));
        await settle(tester);
        expect(e.pendingTemplate?.id, 'builtin_smooth');
        expect(find.byType(TemplatesPage), findsNothing);
        expect(tester.takeException(), isNull);
      });
    },
  );

  testWidgets(
    'save current creates real editable user template while builtins stay intact',
    (tester) async {
      await tester.runAsync(() async {
        final dir = await Directory.systemTemp.createTemp('tiger-template-ui');
        addTearDown(() => dir.delete(recursive: true));
        final e = TemplateEditor(dir),
            store = TemplateStore(Directory('${dir.path}/templates'));
        await tester.pumpWidget(
          MaterialApp(
            home: TemplatesPage(editor: e, store: store),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 30));
        await tester.pumpAndSettle();
        expect(find.text('Smooth'), findsOneWidget);
        await tester.tap(find.byTooltip('Сохранить текущий монтаж'));
        await Future<void>.delayed(const Duration(milliseconds: 30));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Название'),
          'Мой эдит',
        );
        await tester.tap(find.text('Сохранить'));
        await Future<void>.delayed(const Duration(milliseconds: 30));
        await tester.pumpAndSettle();
        await idle(tester);
        final saved = await store.load();
        expect(saved.single.name, 'Мой эдит');
        expect(saved.single.effects.single.type, 'zoom');
        expect(builtinEditTemplates.length, 6);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        e.dispose();
      });
    },
  );
}
