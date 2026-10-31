import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiger_video_edit/dashboard.dart';

void main() {
  double contrast(Color foreground, Color background) {
    final painted = Color.alphaBlend(foreground, background).computeLuminance();
    final backdrop = background.computeLuminance();
    return (painted > backdrop ? painted + .05 : backdrop + .05) /
        (painted > backdrop ? backdrop + .05 : painted + .05);
  }

  Widget dashboard() => TigerDashboard(
    onCreate: () {},
    onProjects: () {},
    onTemplates: () {},
    onMusic: () {},
    onSounds: () {},
    onUpdates: () {},
    onSettings: () {},
    reduceMotion: true,
  );
  Color cardColor(WidgetTester tester) =>
      (tester
                  .widget<AnimatedContainer>(
                    find.ancestor(
                      of: find.text('Новый проект'),
                      matching: find.byType(AnimatedContainer),
                    ),
                  )
                  .decoration
              as BoxDecoration)
          .color!;
  testWidgets('light dashboard text and surfaces retain readable contrast', (
    tester,
  ) async {
    final theme = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
    );
    await tester.pumpWidget(MaterialApp(theme: theme, home: dashboard()));
    await tester.pumpAndSettle();
    final description = tester.widget<Text>(
      find.textContaining('Музыкальные эдиты на твоём устройстве'),
    );
    expect(
      contrast(description.style!.color!, theme.scaffoldBackgroundColor),
      greaterThanOrEqualTo(4.5),
    );
    expect(cardColor(tester).computeLuminance(), greaterThan(.5));
    expect(tester.takeException(), isNull);
  });
  testWidgets('system dashboard follows light and dark platform changes', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(
      MaterialApp(
        themeMode: ThemeMode.system,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.green,
            brightness: Brightness.dark,
          ),
        ),
        home: dashboard(),
      ),
    );
    await tester.pumpAndSettle();
    final light = cardColor(tester);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(
      cardColor(tester).computeLuminance(),
      lessThan(light.computeLuminance()),
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('compact home offers real actions without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var created = 0, settings = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: TigerDashboard(
          onCreate: () => created++,
          onProjects: () {},
          onTemplates: () {},
          onMusic: () {},
          onSounds: () {},
          onUpdates: () {},
          onSettings: () => settings++,
          reduceMotion: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('TIGER'), findsOneWidget);
    await tester.tap(find.text('Новый проект'));
    expect(created, 1);
    await tester.ensureVisible(find.text('Настройки'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Настройки'));
    expect(settings, 1);
    expect(tester.takeException(), isNull);
  });
}
