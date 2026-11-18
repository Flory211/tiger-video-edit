import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiger_video_edit/jamendo.dart';
import 'package:tiger_video_edit/jamendo_page.dart';

import 'jamendo_test.dart' show row;

void main() {
  testWidgets(
    'online phone search is explicit, previews, shows rights and saves favorites',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('tiger-jamendo-ui-');
      addTearDown(() => dir.deleteSync(recursive: true));
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var calls = 0, previews = 0;
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
            previewOverride: (_) async {
              previews++;
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
