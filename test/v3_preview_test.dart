import 'package:tiger_video_edit/timeline_tracks.dart';

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:tiger_video_edit/editor.dart';
import 'package:tiger_video_edit/storage.dart';
import 'package:tiger_video_edit/platform_media.dart'
    show AudioEngine, mediaTool;
import 'package:tiger_video_edit/app_settings.dart';

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiger_video_edit/main.dart';
import 'package:tiger_video_edit/model.dart';
import 'package:tiger_video_edit/compositor.dart';

Future<ui.Image> solid(Color color) async {
  final r = ui.PictureRecorder();
  Canvas(r).drawColor(color, BlendMode.src);
  final p = r.endRecording();
  final image = await p.toImage(8, 8);
  p.dispose();
  return image;
}

class _Streams extends Fake implements PlayerStream {
  @override
  Stream<String> get error => const Stream.empty();
}

class _Player extends Fake implements Player {
  @override
  PlayerStream get stream => _Streams();
  @override
  Future<void> dispose() async {}
  @override
  Future<void> setVolume(double v) async {}
}

class _Audio extends Fake implements AudioEngine {
  @override
  final Player player = _Player();
}

class _ObservedLocalLibrary extends LocalLibrary {
  _ObservedLocalLibrary(super.root);
  final snapshots = <Map<String, dynamic>>[];
  final writes = <Future<void>>[];

  @override
  Future<void> preferences(Map<String, dynamic> data) {
    snapshots.add(Map<String, dynamic>.of(data));
    final write = super.preferences(data);
    writes.add(write);
    return write;
  }
}

// Widget gesture callbacks can register file-write continuations in FakeAsync.
// Drive those microtasks and real I/O until the actual commits finish, rather
// than racing their completion against a fixed elapsed-time budget.
Future<void> _awaitWrites(
  WidgetTester tester,
  List<Future<void>> writes,
) async {
  var done = false;
  Object? error;
  StackTrace? trace;
  final completion = Future.wait(writes).then<void>(
    (_) {
      done = true;
    },
    onError: (Object failure, StackTrace stack) {
      error = failure;
      trace = stack;
      done = true;
    },
  );
  while (!done) {
    await tester.pump();
    await Future<void>.delayed(Duration.zero);
  }
  await completion;
  if (error != null) {
    Error.throwWithStackTrace(error!, trace!);
  }
}

Future<Object?> requestClose(WidgetTester tester) async {
  const codec = StandardMethodCodec();
  final done = Completer<Object?>();
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'tiger/window',
    codec.encodeMethodCall(const MethodCall('requestClose')),
    (ByteData? data) {
      done.complete(data == null ? null : codec.decodeEnvelope(data));
    },
  );
  return done.future;
}

void main() {
  testWidgets(
    'desktop dividers save widths; ctrl click and long press select image groups',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        final dir = await Directory.systemTemp.createTemp('tiger-layout');
        final library = _ObservedLocalLibrary(dir);
        final e = Editor(library, _Audio());
        e.history = ProjectHistory(
          Project(
            images: [
              const Still(path: 'a.mp4'),
              const Still(path: 'b.mp4'),
            ],
          ),
        );
        await tester.pumpWidget(TigerApp(editor: e));
        await tester.pump();
        final left = e.libraryPanelWidth, right = e.propertiesPanelWidth;
        await tester.drag(
          find.byKey(const ValueKey('resize-Медиа')),
          const Offset(40, 0),
        );
        await tester.pump();
        expect(e.libraryPanelWidth, greaterThan(left));
        await tester.drag(
          find.byKey(const ValueKey('resize-Свойства')),
          const Offset(-40, 0),
        );
        await tester.pump();
        expect(e.propertiesPanelWidth, greaterThan(right));
        expect(
          library.snapshots,
          hasLength(2),
          reason: 'Each drag-end requests one real preference write',
        );
        expect(
          library.snapshots.first['libraryPanelWidth'],
          e.libraryPanelWidth,
        );
        expect(
          library.snapshots.last['propertiesPanelWidth'],
          e.propertiesPanelWidth,
        );
        await _awaitWrites(tester, library.writes);
        final persisted = await library.loadPreferences();
        expect(persisted['libraryPanelWidth'], e.libraryPanelWidth);
        expect(persisted['propertiesPanelWidth'], e.propertiesPanelWidth);
        await tester.longPress(find.widgetWithText(ListTile, 'b.mp4'));
        await tester.pump();
        expect(e.selectedImages, {1});
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.tap(find.widgetWithText(ListTile, 'a.mp4'));
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
        expect(e.selectedImages, {0, 1});
        await tester.tap(find.widgetWithText(ListTile, 'b.mp4'));
        await tester.pump();
        expect(e.selectedImages, {1});
        await tester.pumpWidget(const SizedBox());
        await dir.delete(recursive: true);
        expect(tester.takeException(), isNull);
      });
    },
  );

  testWidgets(
    'group mixer saves music and SFX gains as one undoable project change',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('tiger-mixer');
      addTearDown(() => dir.deleteSync(recursive: true));
      final e = Editor(LocalLibrary(dir), _Audio());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 320, child: TimelineTracks(editor: e)),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Громкость музыки и звуков'));
      await tester.pumpAndSettle();
      tester.widget<Slider>(find.byType(Slider).first).onChanged!(.4);
      await tester.pump();
      tester.widget<Slider>(find.byType(Slider).last).onChanged!(1.5);
      await tester.pump();
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(e.project.musicVolume, .4);
      expect(e.project.soundVolume, 1.5);
      expect(e.history.canUndo, isTrue);
      e.history.undo();
      expect(e.project.musicVolume, 1);
      expect(e.project.soundVolume, 1);
      await tester.pumpWidget(const SizedBox());
      e.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'system theme follows platform brightness and reduced motion reaches editor',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('tiger-theme');
      addTearDown(() => dir.deleteSync(recursive: true));
      final e = Editor(LocalLibrary(dir), _Audio());
      e.settings = const AppSettings(
        theme: AppTheme.system,
        reducedMotion: true,
      );
      e.settingsNotifier.value = e.settings;
      tester.binding.platformDispatcher.platformBrightnessTestValue =
          Brightness.light;
      addTearDown(
        tester.binding.platformDispatcher.clearPlatformBrightnessTestValue,
      );
      await tester.pumpWidget(TigerApp(editor: e));
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(EditorScreen));
      expect(Theme.of(context).brightness, Brightness.light);
      expect(
        Theme.of(context).scaffoldBackgroundColor.computeLuminance(),
        greaterThan(.8),
      );
      expect(MediaQuery.disableAnimationsOf(context), isTrue);
      tester.binding.platformDispatcher.platformBrightnessTestValue =
          Brightness.dark;
      await tester.pumpAndSettle();
      expect(Theme.of(context).brightness, Brightness.dark);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'native close channel is Windows-only and preserves dirty projects',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('tiger-close');
      addTearDown(() => dir.deleteSync(recursive: true));
      final e = Editor(LocalLibrary(dir), _Audio());
      await tester.pumpWidget(TigerApp(editor: e));
      await tester.pumpAndSettle();
      e.dirty = true;
      // The native WM_CLOSE bridge exists only in the Windows runner.
      if (!Platform.isWindows) {
        expect(await requestClose(tester), isNull);
        expect(find.text('Несохранённые изменения'), findsNothing);
        expect(e.dirty, isTrue);
        await tester.pumpWidget(const SizedBox());
        expect(tester.takeException(), isNull);
        return;
      }
      final close = requestClose(tester);
      await tester.pumpAndSettle();
      expect(find.text('Несохранённые изменения'), findsOneWidget);
      expect(await requestClose(tester), isFalse);
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      expect(await close, isFalse);
      expect(e.dirty, isTrue);
      e.busy = true;
      expect(await requestClose(tester), isFalse);
      await tester.pump();
      expect(
        find.text(
          'Дождитесь завершения операции или отмените экспорт перед закрытием.',
        ),
        findsOneWidget,
      );
      e.busy = false;
      final discard = requestClose(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Не сохранять'));
      await tester.pumpAndSettle();
      expect(await discard, isTrue);
      await tester.pumpWidget(const SizedBox());
      expect(await requestClose(tester), isNull);
    },
  );
  testWidgets(
    'quality change recreates GIF decoder and replaces paused frame with bounded pixels',
    (tester) async {
      final dir = await tester.runAsync(
        () => Directory.systemTemp.createTemp('tiger-quality'),
      );
      final path = File.fromUri(dir!.uri.resolve('wide.gif')).path;
      await tester.runAsync(() async {
        final result = await Process.run(mediaTool('ffmpeg'), [
          '-v',
          'error',
          '-f',
          'lavfi',
          '-i',
          'color=red:s=1600x100:r=5:d=0.4',
          '-y',
          path,
        ]);
        expect(result.exitCode, 0, reason: result.stderr.toString());
      });
      final item = Still(path: path, durationUs: 400000),
          project = Project(frameRate: 24);
      Future<void> mount(int dimension, {int? expected}) async {
        await tester.pumpWidget(
          MaterialApp(
            home: SizedBox(
              width: 100,
              height: 100,
              child: StillView(
                key: const ValueKey('quality'),
                still: item,
                project: project,
                maxDimension: dimension,
              ),
            ),
          ),
        );
        for (var i = 0; i < 150; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
          final paints = tester
              .widgetList<CustomPaint>(find.byType(CustomPaint))
              .where((p) => p.painter is StillPainter);
          if (paints.isNotEmpty &&
              (paints.first.painter! as StillPainter).image.width ==
                  (expected ?? dimension)) {
            return;
          }
        }
        fail('No paused GIF frame at requested quality');
      }

      await mount(1280);
      await mount(640);
      await mount(1920, expected: 1600);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => dir.delete(recursive: true));
      expect(tester.takeException(), isNull);
    },
  );

  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'paused compositor invalidates decoded previous image and overlay frames',
    () async {
      final a = await solid(Colors.red), b = await solid(Colors.blue);
      const s = Still(path: 'x');
      final p = Project(images: [s]);
      final old = StillPainter(a, s, p, 0, 0);
      expect(
        StillPainter(a, s, p, 0, 0, previousImage: b).shouldRepaint(old),
        isTrue,
      );
      expect(
        StillPainter(
          a,
          s,
          p,
          0,
          0,
          overlays: [VisualFrame(s, b, 0, 1)],
        ).shouldRepaint(old),
        isTrue,
      );
      a.dispose();
      b.dispose();
    },
  );
  test('24fps timeline places image cut at its source-time boundary', () async {
    final p = Project(
      durationUs: 2000000,
      endUs: 2000000,
      frameRate: 24,
      images: [
        const Still(path: 'a'),
        const Still(path: 'b'),
      ],
      markers: [const Marker(id: 'm', timeUs: 1000000)],
    );
    final r = ui.PictureRecorder();
    TimelinePainter(p, [], 0, 1).paint(Canvas(r), const Size(200, 60));
    final pic = r.endRecording(), image = await pic.toImage(200, 60);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    // Both x85 and x95 lie in the first red strip; a stale30fps divisor cuts at80.
    expect(bytes.getUint8((29 * 200 + 90) * 4 + 1), greaterThan(40));
    image.dispose();
    pic.dispose();
  });
}
