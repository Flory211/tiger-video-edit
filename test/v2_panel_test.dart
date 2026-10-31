import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiger_video_edit/editor.dart';
import 'package:tiger_video_edit/model.dart';
import 'package:tiger_video_edit/v2_panel.dart';

class PanelEditor extends ChangeNotifier implements Editor {
  @override
  Project project = Project(
    durationUs: 10000000,
    endUs: 10000000,
    images: [const Still(path: 'clip.mp4', durationUs: 2000000)],
  );
  @override
  int selectedImage = 0;
  @override
  int positionUs = 0;
  @override
  Map<String, EffectPreset> get presets => builtinEffectPresets;
  @override
  void updateStill(Still still) {
    project = project.copy(images: [still]);
    notifyListeners();
  }

  @override
  void upsertCaption(Caption caption) {
    project = project.copy(captions: [caption]);
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> mount(WidgetTester tester, PanelEditor editor) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 228,
            child: ListView(children: [V2Panel(editor: editor)]),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('compact panel validates clip offset before applying it', (
    tester,
  ) async {
    final editor = PanelEditor();
    await mount(tester, editor);
    expect(find.byType(Slider), findsNWidgets(8));
    expect(tester.takeException(), isNull);
    final field = find.widgetWithText(TextFormField, 'Начало клипа, с');
    await tester.ensureVisible(field);
    await tester.enterText(field, '3');
    await tester.tap(find.byTooltip('Применить начало клипа'));
    await tester.pump();
    expect(find.text('Начало должно быть раньше конца клипа'), findsOneWidget);
    expect(editor.project.images.single.sourceStartUs, 0);
    await tester.enterText(field, '1,25');
    await tester.tap(find.byTooltip('Применить начало клипа'));
    await tester.pump();
    expect(editor.project.images.single.sourceStartUs, 1250000);
    expect(tester.takeException(), isNull);
  });

  testWidgets('caption dialog rejects invalid times and preserves cancel', (
    tester,
  ) async {
    final editor = PanelEditor();
    await mount(tester, editor);
    final add = find.text('Добавить титр');
    await tester.ensureVisible(add);
    await tester.pumpAndSettle();
    await tester.tap(add);
    await tester.pumpAndSettle();
    final text = find.widgetWithText(TextFormField, 'Текст');
    final start = find.widgetWithText(
      TextFormField,
      'Начало, с исходного аудио',
    );
    final end = find.widgetWithText(TextFormField, 'Конец, с исходного аудио');
    await tester.enterText(text, 'Первый титр');
    await tester.enterText(start, '5');
    await tester.enterText(end, '4');
    await tester.tap(find.text('Сохранить'));
    await tester.pump();
    expect(find.text('Конец должен быть позже начала'), findsOneWidget);
    expect(editor.project.captions, isEmpty);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(editor.project.captions, isEmpty);
    await tester.ensureVisible(add);
    await tester.pumpAndSettle();
    await tester.tap(add);
    await tester.pumpAndSettle();
    await tester.enterText(text, 'Первый титр');
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(editor.project.captions.single.text, 'Первый титр');
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty project has no effects and disables adding timed text', (
    tester,
  ) async {
    final editor = PanelEditor()..project = Project();
    await mount(tester, editor);
    expect(find.byType(Slider), findsNothing);
    final button = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Добавить титр'),
    );
    expect(button.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });
}
