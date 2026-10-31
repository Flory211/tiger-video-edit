import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:tiger_video_edit/editor.dart';
import 'package:tiger_video_edit/main.dart';
import 'package:tiger_video_edit/main.dart' as app;
import 'package:tiger_video_edit/platform_media.dart';
import 'package:tiger_video_edit/storage.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('v2 native preview and beat assembly', (tester) async {
    const root = String.fromEnvironment(
      'LEOS_ROOT',
      defaultValue: 'C:/LeosFastVideoEditor',
    );
    MediaKit.ensureInitialized(libmpv: '$root/third_party/mpv/libmpv-2.dll');
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('tiger_v2_native'),
    ))!;
    final e = Editor(LocalLibrary(dir), AudioEngine());
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: TigerApp(editor: e),
      ),
    );
    await tester.runAsync(() async {
      await e.openProject('$root/demo/Pulse-v2.tve');
      await e.seek(750000);
    });
    await tester.pumpAndSettle();
    expect(e.project.images[1].kind, 'video');
    expect(e.project.images[2].kind, 'gif');
    expect(e.project.captions.length, 2);
    expect(tester.takeException(), isNull);
    if (find.byType(ListView).evaluate().isNotEmpty) {
      await tester.drag(find.byType(ListView).last, const Offset(0, -370));
      await tester.pumpAndSettle();
    }
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await render.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await tester.runAsync(
      () =>
          File('$root/.tools/native-v2-preview.png')
              .writeAsBytes(data!.buffer.asUint8List()),
    );
    image.dispose();
    await tester.runAsync(() async {
      await e.seek(1250000);
      await e.analyzeBeats();
      expect(e.beatAnalysis!.timesUs.length, greaterThan(5));
      final count = e.project.markers.length;
      e.applyBeats();
      expect(e.project.markers, isNotEmpty);
      await e.undo();
      expect(e.project.markers.length, count);
      e.projectPath = '${dir.path}/v2.tve';
      await e.save();
      final restored = await ProjectStore.read(e.projectPath!);
      expect(restored.captions.length, 2);
      expect(restored.images.first.effects, isNotEmpty);
    });
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => dir.delete(recursive: true));
  }, timeout: const Timeout(Duration(minutes: 3)));
  testWidgets('production bootstrap opens home', (tester) async {
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('tiger_bootstrap_'),
    ))!;
    await tester.runAsync(
      () =>
          File('${dir.path}/app_settings.json')
              .writeAsString('{"autoCheckUpdates":false}'),
    );
    await tester.runAsync(
      () => app
          .main([], libraryOverride: LocalLibrary(dir))
          .timeout(const Duration(seconds: 25)),
    );
    await tester.pumpAndSettle();
    expect(find.text('TIGER'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => dir.delete(recursive: true));
  }, timeout: const Timeout(Duration(minutes: 1)));
  testWidgets('native audio marker save reopen workflow', (tester) async {
    const root = String.fromEnvironment(
      'LEOS_ROOT',
      defaultValue: 'C:/LeosFastVideoEditor',
    );
    MediaKit.ensureInitialized(libmpv: '$root/third_party/mpv/libmpv-2.dll');
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('leos_native'),
    ))!;
    final e = Editor(LocalLibrary(dir), AudioEngine())..countdown = false;
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: TigerApp(editor: e),
      ),
    );
    await tester.runAsync(() async {
      await e.openProject('$root/demo/Pulse.tve');
      e.change(e.project.copy(markers: []));
      await e.toggle();
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.pump();
    expect(e.project.markers.length, 1);
    expect(e.project.markers.first.timeUs, greaterThan(100000));
    expect(e.project.markers.first.timeUs, lessThan(3000000));
    await tester.runAsync(() async {
      await e.stop();
      await e.seek(4000000);
      await e.toggle();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.pump();
    expect(e.project.markers.length, 2);
    expect(e.project.markers.last.timeUs, inInclusiveRange(4000000, 5500000));
    await tester.runAsync(() async {
      await e.stop();
      final times = e.project.markers.map((m) => m.timeUs).toList();
      e.projectPath = '${dir.path}/saved.leos';
      await e.save();
      await e.openProject(e.projectPath);
      expect(e.project.markers.map((m) => m.timeUs), times);
      await e.seek(1000000);
    });
    await tester.pumpAndSettle();
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final screenshot = await render.toImage(pixelRatio: 1);
    final bytes = await screenshot.toByteData(format: ui.ImageByteFormat.png);
    await tester.runAsync(
      () =>
          File('$root/.tools/native-preview.png')
              .writeAsBytes(bytes!.buffer.asUint8List()),
    );
    screenshot.dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => dir.delete(recursive: true));
  }, timeout: const Timeout(Duration(minutes: 4)));
}
