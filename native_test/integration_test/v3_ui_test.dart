import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:tiger_video_edit/app_settings.dart';
import 'package:tiger_video_edit/editor.dart';
import 'package:tiger_video_edit/effect_recipes.dart';
import 'package:tiger_video_edit/main.dart';
import 'package:tiger_video_edit/model.dart';
import 'package:tiger_video_edit/platform_media.dart';
import 'package:tiger_video_edit/sound_library.dart';
import 'package:tiger_video_edit/storage.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'v3 real home/editor/phone routes produce documentation captures',
    (tester) async {
      const root = String.fromEnvironment(
        'LEOS_ROOT',
        defaultValue: 'C:/LeosFastVideoEditor',
      );
      MediaKit.ensureInitialized(libmpv: '$root/third_party/mpv/libmpv-2.dll');
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('tiger_v3_ui'),
      ))!;
      final e = Editor(LocalLibrary(directory), AudioEngine());
      await tester.runAsync(e.initialize);
      e.settings = const AppSettings(
        autoCheckUpdates: false,
        theme: AppTheme.dark,
        reducedMotion: true,
        autosave: false,
      );
      e.settingsNotifier.value = e.settings;
      final boundary = GlobalKey();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1600, 1000);
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: TigerApp(editor: e, showHome: true),
        ),
      );
      Future<void> settle() async {
        for (var i = 0; i < 8; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 60)),
          );
          await tester.pump(const Duration(milliseconds: 80));
        }
      }

      Future<void> capture(String name, int width, int height) async {
        await settle();
        expect(tester.takeException(), isNull);
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: 1);
        expect(image.width, width);
        expect(image.height, height);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await tester.runAsync(
          () =>
              File('$root/docs/$name.png')
                  .writeAsBytes(data!.buffer.asUint8List(), flush: true),
        );
        image.dispose();
      }

      await capture('V3_HOME', 1600, 1000);
      await tester.tap(find.text('Новый проект'));
      await settle();
      expect(find.byType(EditorScreen), findsOneWidget);
      // Exercise the actual editor name dialog after entering from the real home.
      await tester.tap(find.byType(PopupMenuButton<String>));
      await settle();
      await tester.tap(find.text('Новый проект').last);
      await settle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Название'),
        'Tiger Video Edit 3 — демонстрация',
      );
      await tester.tap(find.text('Готово'));
      await settle();
      await tester.runAsync(() async {
        await e.openProject('$root/demo/Pulse-v2.tve');
        final project = e.project;
        e.change(
          project.copy(
            name: 'Tiger Video Edit 3 — Effects & Layers',
            frameRate: 24,
            captions: [
              for (final caption in project.captions)
                caption.copy(
                  text: caption.id == 'title'
                      ? 'TIGER VIDEO EDIT 3'
                      : caption.text,
                ),
            ],
            visualClips: [
              VisualClip(
                id: 'demo-overlay',
                media: project.images[2].copy(
                  scale: .34,
                  x: .28,
                  y: -.24,
                  cover: false,
                ),
                startUs: 0,
                durationUs: 2000000,
                track: 1,
                opacity: .8,
              ),
            ],
          ),
        );
        e.addGlobalEffect(
          effectRecipes.firstWhere((r) => r.name == 'Soft Glow'),
        );
        final sounds = await SoundLibrary(Directory('${directory.path}/sounds'))
            .generate();
        await e.seek(750000);
        e.addSound(sounds.firstWhere((s) => s.id == 'impact'));
      });
      await capture('V3_EDITOR', 1600, 1000);
      expect(e.project.globalEffects, isNotEmpty);
      expect(e.project.visualClips, isNotEmpty);
      expect(e.project.audioClips, isNotEmpty);
      tester.view.physicalSize = const Size(540, 960);
      await tester.binding.setSurfaceSize(const Size(540, 960));
      await capture('V3_PHONE', 540, 960);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.runAsync(() => directory.delete(recursive: true));
      await tester.binding.setSurfaceSize(null);
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
