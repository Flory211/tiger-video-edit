import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiger_video_edit/app_settings.dart';
import 'package:tiger_video_edit/music_library.dart';
import 'package:tiger_video_edit/service_pages.dart';
import 'package:tiger_video_edit/sound_library.dart';
import 'package:tiger_video_edit/update_service.dart';

void main() {
  testWidgets('settings switches emit typed changes', (tester) async {
    AppSettings? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          settings: const AppSettings(),
          onChanged: (value) async {
            saved = value;
          },
        ),
      ),
    );
    await tester.tap(find.text('Уменьшить анимации'));
    await tester.pumpAndSettle();
    expect(saved?.reducedMotion, true);
  });
  testWidgets('local music empty view shows honest online source status', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MusicLibraryPage(
          library: _EmptyMusicLibrary(),
          onUse: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Jamendo'), findsOneWidget);
    expect(find.text('Импортировать музыку'), findsWidgets);
  });
  testWidgets('unconfigured updates show configuration and manual check', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: UpdatesPage(
          service: UpdateService(
            owner: '',
            cacheFile: File('unused-cache.json'),
          ),
          currentVersion: '3.0.0',
          platform: UpdatePlatform.windowsX64,
          downloadDirectory: Directory.systemTemp,
          onOpenDownloaded: (_) async {},
        ),
      ),
    );
    expect(find.textContaining('TVE_GITHUB_OWNER'), findsOneWidget);
    expect(find.text('Проверить обновления'), findsOneWidget);
    await tester.tap(find.text('Проверить обновления'));
    await tester.pumpAndSettle();
    expect(find.text('Публичный релиз пока не настроен'), findsOneWidget);
  });
  testWidgets(
    'sound actions work on a phone without starting the preview player',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final actions = <bool>[];
      await tester.pumpWidget(
        MaterialApp(
          home: SoundLibraryPage(
            library: _StaticSoundLibrary(),
            onAdd: (sound, atMarkers) {
              actions.add(atMarkers);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('На таймлайн').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('На маркеры').first);
      await tester.pumpAndSettle();
      expect(actions, [false, true]);
      expect(tester.takeException(), isNull);
    },
  );
}

class _EmptyMusicLibrary extends MusicLibrary {
  _EmptyMusicLibrary() : super(Directory.systemTemp);
  @override
  Future<void> load() async {}
}

class _StaticSoundLibrary extends SoundLibrary {
  _StaticSoundLibrary() : super(Directory.systemTemp);
  @override
  Future<List<SoundEffect>> generate() async => [
    const SoundEffect(
      id: 'whoosh',
      name: 'Whoosh',
      path: 'unused.wav',
      duration: Duration(milliseconds: 650),
    ),
  ];
}
