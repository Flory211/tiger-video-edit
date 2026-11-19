import 'dart:io';
import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:tiger_video_edit/jamendo.dart';
import 'package:tiger_video_edit/jamendo_page.dart';

import 'jamendo_test.dart' show row;

class _PreviewStreams extends Fake implements PlayerStream {
  final errors = StreamController<String>.broadcast();
  final ended = StreamController<bool>.broadcast();
  final positions = StreamController<Duration>.broadcast();
  @override
  Stream<String> get error => errors.stream;
  @override
  Stream<bool> get completed => ended.stream;
  @override
  Stream<Duration> get position => positions.stream;
}

class _PreviewPlayer extends Fake implements Player {
  final events = _PreviewStreams();
  final void Function() opened;
  bool disposed = false;
  _PreviewPlayer(this.opened);
  @override
  _PreviewStreams get stream => events;
  @override
  PlatformPlayer? get platform => null;
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    opened();
    scheduleMicrotask(
      () => events.positions.add(const Duration(milliseconds: 100)),
    );
  }

  @override
  Future<void> dispose() async {
    if (disposed) return;
    disposed = true;
    await events.errors.close();
    await events.ended.close();
    await events.positions.close();
  }
}

void main() {
  testWidgets(
    'short phone with keyboard and landscape keep the library scrollable',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(() {
        tester.view.resetViewInsets();
        return tester.binding.setSurfaceSize(null);
      });
      final dir = Directory.systemTemp.createTempSync('tiger-music-keyboard-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final provider = JamendoProvider(
        clientId: 'fixture-id',
        getJson: (_) async => {
          'headers': {'status': 'success'},
          'results': [row()],
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: JamendoMusicPage(
            provider: provider,
            configFile: File('${dir.path}/config.json'),
            workingDirectory: dir,
            onUse: (_) async {},
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Найти'));
      await tester.tap(find.text('Найти'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(find.text('Piano'), findsOneWidget);
      expect(tester.takeException(), isNull);
      tester.view.resetViewInsets();
      await tester.binding.setSurfaceSize(const Size(640, 360));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(find.text('Piano'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'phone phonk shortcut clears unrelated filters and exposes sorting',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final dir = Directory.systemTemp.createTempSync('tiger-phonk-ui-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final requests = <Map<String, String>>[];
      final provider = JamendoProvider(
        clientId: 'fixture-id',
        getJson: (params) async {
          requests.add(params);
          return {
            'headers': {'status': 'success'},
            'results': [row()],
          };
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: JamendoMusicPage(
            provider: provider,
            configFile: File('${dir.path}/config.json'),
            workingDirectory: dir,
            onUse: (_) async {},
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pumpAndSettle();
      expect(requests, isEmpty);
      await tester.tap(find.text('CC BY / CC0'));
      await tester.tap(find.byKey(const ValueKey('jamendo-genre')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Классика').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('jamendo-quick-phonk')));
      await tester.pumpAndSettle();
      expect(requests.single['namesearch'], 'phonk');
      expect(requests.single.containsKey('tags'), false);
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'CC BY / CC0'))
            .selected,
        false,
      );
      expect(find.text('Piano'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('jamendo-sort')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Сначала новые').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Разные авторы'));
      await tester.tap(find.text('Найти'));
      await tester.pumpAndSettle();
      expect(requests.last['order'], 'releasedate_desc');
      expect(requests.last['groupby'], 'artist_id');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Back cancels pending import before the exit animation finishes',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('tiger-jamendo-back-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final metadata = Completer<Map<String, dynamic>>();
      var refreshStarted = false, audioOpened = false, imported = false;
      final provider = JamendoProvider(
        clientId: 'fixture-id',
        editingApproved: true,
        getJson: (params) async {
          if (params.containsKey('id')) {
            refreshStarted = true;
            return metadata.future;
          }
          return {
            'headers': {'status': 'success'},
            'results': [row()],
          };
        },
        audioStream: (_) {
          audioOpened = true;
          return Stream.value([1, 2, 3]);
        },
      );
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(navigatorKey: navigator, home: const Scaffold()),
      );
      unawaited(
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => JamendoMusicPage(
              provider: provider,
              configFile: File('${dir.path}/config.json'),
              workingDirectory: dir,
              onUse: (_) async {
                imported = true;
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Найти'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Piano'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'В проект'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('В проект'));
      await tester.pump();
      expect(refreshStarted, true);
      navigator.currentState!.pop();
      // Complete metadata while the outgoing route is still mounted.
      metadata.complete({
        'headers': {'status': 'success'},
        'results': [row()],
      });
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pumpAndSettle();
      expect(audioOpened, false);
      expect(imported, false);
      expect(dir.listSync(), isEmpty);
    },
  );
  testWidgets(
    'cancel is disabled after project import starts and temporary audio is removed',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync(
        'tiger-jamendo-import-ui-',
      );
      addTearDown(() => dir.deleteSync(recursive: true));
      final entered = Completer<void>(), finish = Completer<void>();
      addTearDown(() {
        if (!finish.isCompleted) finish.complete();
      });
      final provider = JamendoProvider(
        clientId: 'fixture-id',
        editingApproved: true,
        getJson: (_) async => {
          'headers': {'status': 'success'},
          'results': [row()],
        },
        audioStream: (_) => Stream.value([1, 2, 3]),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: JamendoMusicPage(
            provider: provider,
            configFile: File('${dir.path}/config.json'),
            workingDirectory: dir,
            onUse: (track) async {
              expect(await File(track.path).exists(), true);
              entered.complete();
              await finish.future;
            },
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Найти'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Piano'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'В проект'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('В проект'));
      for (var i = 0; i < 100 && !entered.isCompleted; i++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      expect(entered.isCompleted, true);
      await tester.pump();
      expect(find.text('Добавление в проект…'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Отменить'))
            .onPressed,
        isNull,
      );
      finish.complete();
      for (
        var i = 0;
        i < 100 && find.text('Добавление в проект…').evaluate().isNotEmpty;
        i++
      ) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      expect(
        dir.listSync().whereType<File>().where(
          (f) => f.path.endsWith('.mp3') || f.path.endsWith('.part'),
        ),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'pagination keeps submitted query after edits and failed new search',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('tiger-jamendo-pages-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final requests = <Map<String, String>>[];
      final provider = JamendoProvider(
        clientId: 'fixture-id',
        getJson: (params) async {
          requests.add(params);
          if (params['search'] == 'bad') {
            throw const JamendoException('Поиск не выполнен');
          }
          return {
            'headers': {'status': 'success'},
            'results': List.generate(
              20,
              (i) => {
                ...row(),
                'id': '${int.parse(params['offset']!) + i + 1}',
                'name': '${params['search']}-${params['offset']}-$i',
              },
            ),
          };
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: JamendoMusicPage(
            configFile: File('${dir.path}/config.json'),
            workingDirectory: dir,
            onUse: (_) async {},
            provider: provider,
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'piano');
      await tester.tap(find.text('Найти'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Следующая страница'));
      await tester.pumpAndSettle();
      expect(find.text('Страница 2'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'ambient');
      await tester.tap(find.byKey(const ValueKey('jamendo-sort')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Сначала новые').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Разные авторы'));
      await tester.tap(find.byTooltip('Предыдущая страница'));
      await tester.pumpAndSettle();
      expect(find.text('piano-0-0'), findsOneWidget);
      expect(requests.last['order'], 'relevance');
      expect(requests.last.containsKey('groupby'), false);
      await tester.tap(find.byTooltip('Следующая страница'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'bad');
      await tester.tap(find.text('Найти'));
      await tester.pumpAndSettle();
      expect(find.text('Поиск не выполнен'), findsOneWidget);
      await tester.tap(find.byTooltip('Предыдущая страница'));
      await tester.pumpAndSettle();
      expect(find.text('piano-0-0'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'online phone search is explicit, previews, shows rights and saves favorites',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('tiger-jamendo-ui-');
      addTearDown(() => dir.deleteSync(recursive: true));
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var calls = 0, previews = 0;
      final players = <_PreviewPlayer>[];
      final provider = JamendoProvider(
        clientId: 'fixture-id',
        getJson: (params) async {
          calls++;
          return {
            'headers': {'status': 'success'},
            'results': [row()],
          };
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: JamendoMusicPage(
            configFile: File('${dir.path}/config.json'),
            workingDirectory: dir,
            provider: provider,
            playerFactory: () {
              final p = _PreviewPlayer(() => previews++);
              players.add(p);
              return p;
            },
            onUse: (_) async => fail('editing is not approved'),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pumpAndSettle();
      expect(calls, 0);
      await tester.enterText(find.byType(TextField), 'piano');
      await tester.tap(find.text('Найти'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.text('Piano'), findsOneWidget);
      await tester.tap(find.byTooltip('Прослушать'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pumpAndSettle();
      expect(previews, 1);
      players.last.events.ended.add(true);
      for (var i = 0; i < 100 && !players.last.disposed; i++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      await tester.pumpAndSettle();
      expect(find.byTooltip('Остановить'), findsNothing);
      await tester.tap(find.byTooltip('Прослушать'));
      for (var i = 0; i < 100 && previews < 2; i++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      expect(previews, 2);
      await tester.tap(find.byTooltip('В избранное'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Избранное'));
      await tester.pumpAndSettle();
      expect(find.text('Piano'), findsOneWidget);
      await tester.tap(find.text('Piano'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('ожидает подтверждения Jamendo'),
        findsOneWidget,
      );
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'В проект'),
      );
      expect(button.onPressed, isNull);
      var saved = false;
      for (var i = 0; i < 100 && !saved; i++) {
        await tester.pump();
        saved = (await tester.runAsync(() async {
          final file = File('${dir.path}/config.json.library.json');
          try {
            final json = jsonDecode(await file.readAsString()) as Map;
            return (json['favorites'] as List).isNotEmpty;
          } on FileSystemException {
            // An atomic replacement can be between backup and final rename.
            return false;
          }
        }))!;
        if (!saved) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
        }
      }
      expect(
        saved,
        isTrue,
        reason: 'Favorite must reach the durable catalog before cleanup.',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'search failure is visible and can be retried without clearing local music',
    (tester) async {
      var calls = 0;
      final dir = Directory.systemTemp.createTempSync('tiger-jamendo-error-');
      addTearDown(() => dir.deleteSync(recursive: true));
      await tester.pumpWidget(
        MaterialApp(
          home: JamendoMusicPage(
            configFile: File('${dir.path}/config.json'),
            workingDirectory: dir,
            onUse: (_) async {},
            provider: JamendoProvider(
              clientId: 'fixture-id',
              getJson: (_) async {
                calls++;
                if (calls == 1) throw const JamendoException('Нет интернета');
                return {
                  'headers': {'status': 'success'},
                  'results': [row()],
                };
              },
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Найти'));
      await tester.pumpAndSettle();
      expect(find.text('Нет интернета'), findsOneWidget);
      await tester.tap(find.text('Найти'));
      await tester.pumpAndSettle();
      expect(find.text('Piano'), findsOneWidget);
      expect(calls, 2);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
