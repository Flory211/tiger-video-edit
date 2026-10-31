import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiger_video_edit/editor.dart';
import 'package:tiger_video_edit/model.dart';
import 'package:tiger_video_edit/app_settings.dart';
import 'package:tiger_video_edit/effect_recipes.dart';
import 'package:tiger_video_edit/v3_panel.dart';

class TestEditor extends ChangeNotifier implements Editor {
  @override
  Project project = Project(
    audio: 'a.wav',
    durationUs: 10000000,
    endUs: 10000000,
    images: [const Still(path: 'x')],
  );
  @override
  int selectedImage = 0;
  @override
  Set<int> selectedImages = {0};
  @override
  AppSettings settings = const AppSettings(reducedMotion: true);
  @override
  Future<void> updateSettings(AppSettings next) async {
    settings = next;
    notifyListeners();
  }

  @override
  void updateStill(Still s) {
    project = project.copy(images: [s]);
    notifyListeners();
  }

  int applications = 0;
  @override
  void applyEffectRecipe(EffectRecipe r, {bool all = false}) {
    applications++;
    updateStill(project.images.first.copy(effectStack: r.effects));
  }

  @override
  void setGlobalEffectsEnabled(bool enabled) {
    project = project.copy(globalEffectsEnabled: enabled);
    notifyListeners();
  }

  @override
  void addGlobalEffect(
    EffectRecipe r, {
    GlobalEffectMode mode = GlobalEffectMode.always,
    int? startUs,
    int? endUs,
    List<String>? markerIds,
  }) {
    project = project.copy(
      globalEffects: [
        GlobalAdjustmentLayer(
          id: 'test-layer',
          mode: mode,
          startUs: startUs ?? 0,
          endUs: endUs ?? project.endUs,
          markerIds: markerIds ?? [],
          effects: r.effects,
        ),
      ],
    );
    notifyListeners();
  }

  @override
  void updateGlobalLayer(GlobalAdjustmentLayer l) {
    project = project.copy(globalEffects: [l]);
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<void> mountPanel(WidgetTester tester, TestEditor e) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ListView(children: [V3Panel(editor: e)]),
      ),
    ),
  );
}

void main() {
  testWidgets('favorites persist and animation form saves numeric keys', (
    tester,
  ) async {
    final e = TestEditor();
    await mountPanel(tester, e);
    await tester.tap(find.text('Библиотека стилей'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Поиск стиля'),
      'Elastic Zoom',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Избранное: Elastic Zoom'));
    await tester.pumpAndSettle();
    expect(e.settings.favoriteEffects, contains('Elastic Zoom'));
    await tester.tap(find.byTooltip('Закрыть библиотеку'));
    await tester.pumpAndSettle();
    final add = find.text('Добавить анимацию');
    await tester.ensureVisible(add);
    await tester.pumpAndSettle();
    await tester.tap(add);
    await tester.pumpAndSettle();
    final field = find.widgetWithText(TextFormField, 'Значение ключа 2');
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.enterText(field, '1.8');
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(e.project.images.single.animations.single.keyframes.last.value, 1.8);
    expect(tester.takeException(), isNull);
  });
  testWidgets('global range validates bounds and updates only layer', (
    tester,
  ) async {
    final e = TestEditor();
    e.project = e.project.copy(
      globalEffects: [
        const GlobalAdjustmentLayer(
          id: 'layer',
          effects: [EffectInstance(id: 'e', type: 'flash')],
        ),
      ],
    );
    await mountPanel(tester, e);
    final tile = find.text('Слой layer');
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    final edit = find.text('Режим и время');
    await tester.ensureVisible(edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<GlobalEffectMode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отрезок времени').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Начало, с'),
      '5',
    );
    await tester.enterText(find.widgetWithText(TextFormField, 'Конец, с'), '4');
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(find.text('Конец должен быть позже начала'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Конец, с'), '6');
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(e.project.globalEffects.single.mode, GlobalEffectMode.range);
    expect(e.project.globalEffects.single.startUs, 5000000);
    expect(e.project.globalEffects.single.endUs, 6000000);
    expect(e.project.images.single.effectStack, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'phone library scrolls preview and applies distinct global layer',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final e = TestEditor();
      await mountPanel(tester, e);
      await tester.tap(find.text('Библиотека стилей'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Поиск стиля'),
        'Soft Glow',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Soft Glow'));
      await tester.pumpAndSettle();
      final add = find.widgetWithText(TextButton, 'Добавить глобальный слой');
      await tester.ensureVisible(add);
      await tester.pumpAndSettle();
      await tester.tap(add);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(e.project.globalEffects.single.effects.single.type, 'glow');
      expect(e.project.images.single.effectStack, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('effect form rejects invalid strength and saves actual values', (
    tester,
  ) async {
    final e = TestEditor();
    e.project = e.project.copy(
      images: [
        const Still(
          path: 'x',
          effectStack: [EffectInstance(id: 'e', type: 'zoom')],
        ),
      ],
    );
    await mountPanel(tester, e);
    await tester.ensureVisible(find.text('zoom'));
    await tester.tap(find.text('zoom'));
    await tester.pumpAndSettle();
    final strength = find.widgetWithText(TextFormField, 'Сила');
    await tester.enterText(strength, 'NaN');
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(find.text('Допустимо: 0.0 … 1.0'), findsOneWidget);
    expect(e.project.images.single.effectStack.single.strength, .5);
    await tester.enterText(strength, '0.7');
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(e.project.images.single.effectStack.single.strength, .7);
    expect(tester.takeException(), isNull);
  });
  testWidgets('keyframe editor rejects duplicate times and preserves cancel', (
    tester,
  ) async {
    final e = TestEditor();
    await mountPanel(tester, e);
    final add = find.text('Добавить анимацию');
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pumpAndSettle();
    final second = find.widgetWithText(TextFormField, 'Время ключа 2, с');
    await tester.ensureVisible(second);
    await tester.enterText(second, '0');
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(
      find.text('Время каждого ключа должно быть уникальным'),
      findsOneWidget,
    );
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(e.project.images.single.animations, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'compact panel opens searchable recipes and applies actual stack',
    (tester) async {
      final e = TestEditor();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 228,
              child: ListView(children: [V3Panel(editor: e)]),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Библиотека стилей'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Поиск стиля'),
        'Elastic Zoom',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Elastic Zoom'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('К выбранным'));
      await tester.pumpAndSettle();
      expect(e.applications, 1);
      expect(e.project.images.single.effectStack.single.type, 'zoom');
      expect(tester.takeException(), isNull);
    },
  );
}
