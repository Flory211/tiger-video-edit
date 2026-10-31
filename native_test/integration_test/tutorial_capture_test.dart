import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:tiger_video_edit/editor.dart';
import 'package:tiger_video_edit/main.dart';
import 'package:tiger_video_edit/platform_media.dart';
import 'package:tiger_video_edit/storage.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('capture real tutorial interface states', (tester) async {
    const root = String.fromEnvironment(
      'LEOS_ROOT',
      defaultValue: 'C:/LeosFastVideoEditor',
    );
    MediaKit.ensureInitialized(libmpv: '$root/third_party/mpv/libmpv-2.dll');
    final temp = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('tiger_tutorial_'),
    ))!;
    final output = Directory('$root/tutorial/assets');
    await tester.runAsync(() => output.create(recursive: true));
    final e = Editor(LocalLibrary(temp), AudioEngine());
    final boundary = GlobalKey();
    final captures = <String, dynamic>{};
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: TigerApp(editor: e),
      ),
    );

    Future<void> settle() async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
    }

    Future<void> capture(String key, {Rect? focus}) async {
      await settle();
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await render.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await tester.runAsync(
        () =>
            File('${output.path}/$key.png')
                .writeAsBytes(bytes!.buffer.asUint8List()),
      );
      final labels = <String, String>{
        'new_menu': 'Меню проекта',
        'new_dialog': 'Название нового проекта',
        'library': 'Порядок медиа',
        'format_landscape': 'Выбор формата',
        'format_portrait': 'Вертикальный формат',
        'image_properties': 'Кадрирование и масштаб',
        'trim': 'Границы музыкального отрывка',
        'marker_properties': 'Точное время маркера',
        'beat_dialog': 'Чувствительность анализа',
        'beat_result': 'Подтверждение замены маркеров',
        'effects': 'Сила эффектов',
        'preset': 'Управление пресетами',
        'preset_save': 'Имя пользовательского пресета',
        'video_properties': 'Начало исходного клипа',
        'captions': 'Список титров',
        'caption_dialog': 'Текст и время титра',
        'save_menu': 'Сохранение и восстановление',
        'recent': 'Последние проекты',
        'settings': 'Клавиша, отсчёт и автосохранение',
        'export': 'Прогресс и отмена экспорта',
        'missing': 'Отсутствующие исходники',
        'mobile_preview': 'Компактный экран: просмотр',
        'mobile_media': 'Компактный экран: медиа',
        'mobile_properties': 'Компактный экран: свойства',
      };
      final propertyKeys = {
        'image_properties',
        'trim',
        'marker_properties',
        'effects',
        'preset',
        'video_properties',
        'captions',
      };
      final dialogKeys = {
        'new_dialog',
        'beat_dialog',
        'beat_result',
        'preset_save',
        'recent',
        'settings',
      };
      final rect = key == 'trim'
          ? const Rect.fromLTWH(1340, 575, 260, 170)
          : key == 'image_properties'
          ? const Rect.fromLTWH(1340, 100, 260, 310)
          : key == 'marker_properties'
          ? const Rect.fromLTWH(1340, 65, 260, 260)
          : key == 'effects'
          ? const Rect.fromLTWH(1340, 65, 260, 520)
          : key == 'format_landscape' || key == 'format_portrait'
          ? const Rect.fromLTWH(1180, 65, 150, 80)
          : key == 'timeline_zoom'
          ? const Rect.fromLTWH(1240, 760, 360, 100)
          : key == 'countdown'
          ? const Rect.fromLTWH(600, 230, 380, 350)
          : key == 'export'
          ? const Rect.fromLTWH(0, 55, 700, 95)
          : key == 'missing'
          ? const Rect.fromLTWH(0, 55, 750, 100)
          : key == 'video_properties' || key == 'gif'
          ? const Rect.fromLTWH(1340, 305, 260, 80)
          : key == 'captions'
          ? const Rect.fromLTWH(1340, 375, 260, 255)
          : key == 'preset'
          ? const Rect.fromLTWH(1340, 180, 260, 195)
          : key == 'library'
          ? const Rect.fromLTWH(0, 70, 238, 330)
          : propertyKeys.contains(key)
          ? const Rect.fromLTWH(1340, 100, 260, 490)
          : dialogKeys.contains(key)
          ? const Rect.fromLTWH(500, 260, 600, 480)
          : key == 'caption_dialog'
          ? const Rect.fromLTWH(596, 245, 410, 490)
          : key == 'new_menu' || key == 'save_menu'
          ? const Rect.fromLTWH(1350, 50, 250, 370)
          : focus ??
                Rect.fromLTWH(
                  0,
                  0,
                  image.width.toDouble(),
                  image.height.toDouble(),
                );
      captures[key] = {
        'file': '$key.png',
        'width': image.width,
        'height': image.height,
        'focus': {
          'x': rect.left,
          'y': rect.top,
          'w': rect.width,
          'h': rect.height,
          'label': labels[key] ?? 'Рабочее окно',
        },
        'label': labels[key] ?? 'Рабочее окно',
      };
      image.dispose();
      print('TUTORIAL_CAPTURE $key');
    }

    Future<void> tapText(String text) async {
      await tester.tap(find.text(text).last);
      await settle();
    }

    Future<void> menu() async {
      await tester.tap(find.byType(PopupMenuButton<String>));
      await settle();
    }

    Future<void> propsTop() async {
      final list = find.byType(ListView).first;
      await tester.drag(list, const Offset(0, 2200));
      await settle();
    }

    Future<void> reveal(String text) async {
      for (var i = 0; i < 14; i++) {
        final target = find.text(text);
        if (target.evaluate().isNotEmpty) {
          await tester.ensureVisible(target.last);
          await settle();
          return;
        }
        await tester.drag(find.byType(ListView).first, const Offset(0, -300));
        await settle();
      }
      throw StateError('Cannot reveal $text');
    }

    Future<void> openDemo() async {
      await tester.runAsync(() async {
        await e.openProject('$root/demo/Pulse-v2.tve');
        e.projectPath = '${temp.path}/tutorial.tve';
        await e.seek(750000);
      });
      await settle();
    }

    const remaining = bool.fromEnvironment('CAPTURE_REMAINING');
    if (!remaining) {
      await capture('empty');
      await menu();
      await capture('new_menu', focus: const Rect.fromLTWH(1150, 0, 450, 600));
      await tapText('Новый проект');
      await tester.enterText(find.byType(TextField).last, 'Мой первый эдит');
      await capture(
        'new_dialog',
        focus: const Rect.fromLTWH(450, 230, 700, 500),
      );
      await tapText('Готово');
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await openDemo();
      await capture('overview');
      final original = e.project;
      e.change(original.copy(images: [], markers: [], captions: []));
      await capture('audio_ready');
      e.change(original);
      await capture('library', focus: const Rect.fromLTWH(0, 60, 350, 700));
      await capture(
        'format_landscape',
        focus: const Rect.fromLTWH(238, 60, 1102, 730),
      );
      e.change(e.project.copy(portrait: true));
      await capture(
        'format_portrait',
        focus: const Rect.fromLTWH(238, 60, 1102, 730),
      );
      e.change(e.project.copy(portrait: false));
      e.inspectImage = true;
      e.refresh();
      await propsTop();
      await capture(
        'image_properties',
        focus: const Rect.fromLTWH(1100, 65, 500, 720),
      );
      await reveal('Музыкальный отрывок');
      await capture('trim', focus: const Rect.fromLTWH(1100, 65, 500, 720));
      await propsTop();

      // Start the real countdown and capture while its timer is running.
      await tester.runAsync(() async {
        await e.seek(0);
        e.toggle();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await capture(
        'countdown',
        focus: const Rect.fromLTWH(238, 60, 1102, 730),
      );
      await tester.runAsync(e.stop);
      await capture('markers', focus: const Rect.fromLTWH(0, 750, 1600, 250));
      e.selectedMarker = e.project.markers[2].id;
      e.refresh();
      await capture(
        'marker_properties',
        focus: const Rect.fromLTWH(1100, 65, 500, 720),
      );
      e.zoom = 5;
      e.refresh();
      await capture(
        'timeline_zoom',
        focus: const Rect.fromLTWH(0, 750, 1600, 250),
      );
      e.zoom = 1;
      e.selectedMarker = null;
      await tester.runAsync(() => e.seek(2600000));
      await capture('preview', focus: const Rect.fromLTWH(238, 60, 1102, 730));

      await menu();
      await tapText('Ритм и автосборка');
      await capture(
        'beat_dialog',
        focus: const Rect.fromLTWH(400, 200, 800, 600),
      );
      await tester.tap(find.text('Анализировать'));
      await tester.runAsync(() async {
        for (var i = 0; i < 100; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          if (e.beatAnalysis != null && !e.busy) break;
        }
      });
      await capture(
        'beat_result',
        focus: const Rect.fromLTWH(400, 200, 800, 600),
      );
      await tapText('Автосборка');
      await capture(
        'auto_markers',
        focus: const Rect.fromLTWH(0, 750, 1600, 250),
      );

      e.selectedImage = 0;
      e.inspectImage = true;
      e.refresh();
      await reveal('ЭФФЕКТЫ');
      await capture('effects', focus: const Rect.fromLTWH(1100, 65, 500, 720));
      await reveal('Сохранить текущие');
      await capture('preset', focus: const Rect.fromLTWH(1100, 65, 500, 720));
      await tapText('Сохранить текущие');
      await tester.enterText(find.byType(TextFormField).last, 'Мягкий удар');
      await capture(
        'preset_save',
        focus: const Rect.fromLTWH(400, 200, 800, 600),
      );
      await tapText('Сохранить');
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)),
      );

      e.selectedImage = 1;
      e.refresh();
      await reveal('Начало клипа, с');
      await capture(
        'video_properties',
        focus: const Rect.fromLTWH(1100, 65, 500, 720),
      );
      e.selectedImage = 2;
      e.refresh();
      await capture('gif');
      await reveal('Добавить титр');
      await tapText('Добавить титр');
      await tester.enterText(
        find
            .descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(TextFormField),
            )
            .first,
        'Мой первый эдит',
      );
      await capture(
        'caption_dialog',
        focus: const Rect.fromLTWH(420, 50, 760, 900),
      );
      await tapText('Сохранить');
      await capture('captions', focus: const Rect.fromLTWH(1100, 65, 500, 720));
      await propsTop();
      await tester.runAsync(e.save);
      await menu();
      await capture('save_menu', focus: const Rect.fromLTWH(1150, 0, 450, 600));
      await tapText('Последние проекты');
      await capture('recent', focus: const Rect.fromLTWH(350, 180, 900, 640));
      await tester.tapAt(const Offset(50, 500));
      await settle();
      await tester.tap(find.byTooltip('Настройки'));
      await capture('settings', focus: const Rect.fromLTWH(350, 120, 900, 760));
      await tapText('Сохранить');

      // Render a real export without displaying a native file picker.
      await tester.runAsync(e.stop);
      e.exporting = true;
      e.progress = 0;
      e.refresh();
      await capture('export', focus: const Rect.fromLTWH(0, 60, 1600, 180));
      await tester.runAsync(() async {
        await e.exporter.export(e.project, '${temp.path}/tutorial-result.mp4', (
          value,
        ) {
          e.progress = value;
          e.refresh();
        });
      });
      e.exporting = false;
      e.refresh();
    } else {
      await openDemo();
    }
    await capture('export_done');

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(540, 960);
    await tester.binding.setSurfaceSize(const Size(540, 960));
    await capture('mobile_preview');
    await tapText('Медиа');
    await capture('mobile_media');
    await tapText('Свойства');
    await capture('mobile_properties');
    tester.view.physicalSize = const Size(1600, 1000);
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    final current = e.project;
    final absent = current.copy(
      images: [
        current.images.first.copy(path: '${temp.path}/missing-image.png'),
      ],
    );
    await tester.runAsync(() async {
      final path = '${temp.path}/missing.tve';
      await ProjectStore.save(path, absent);
      await e.openProject(path);
    });
    await capture('missing');

    final manifestFile = File('${output.path}/manifest.json');
    await tester.runAsync(() async {
      if (await manifestFile.exists()) {
        final previous = jsonDecode(await manifestFile.readAsString()) as Map;
        final previousCaptures = previous['captures'] as Map? ?? {};
        for (final entry in previousCaptures.entries) {
          captures.putIfAbsent(entry.key as String, () => entry.value);
        }
      }
    });
    await tester.runAsync(
      () => manifestFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'source': 'Real Flutter Windows integration test',
          'focusUnits': 'pixels',
          'captures': captures,
        }),
      ),
    );
    final script = jsonDecode(
      await tester.runAsync(
        () => File('$root/tutorial/script.json').readAsString(),
      ) as String,
    ) as Map;
    final required =
        (script['scenes'] as List)
            .expand((s) => (s['shots'] as List).cast<String>())
            .toSet()
          ..remove('result_clip');
    final existing = (await tester.runAsync(
      () => output
          .list()
          .where((f) => f.path.endsWith('.png'))
          .map(
            (f) => f.path
                .replaceAll('\\', '/')
                .split('/')
                .last
                .replaceAll('.png', ''),
          )
          .toList(),
    ))!;
    expect(existing.toSet(), containsAll(required));
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    await tester.runAsync(() => temp.delete(recursive: true));
  }, timeout: const Timeout(Duration(minutes: 15)));
}
