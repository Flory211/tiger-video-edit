import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:tiger_video_edit/jamendo.dart';
import 'package:tiger_video_edit/jamendo_page.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real Jamendo search and stream with desktop/phone library', (
    tester,
  ) async {
    const clientId = String.fromEnvironment('TVE_JAMENDO_CLIENT_ID');
    const root = String.fromEnvironment(
      'LEOS_ROOT',
      defaultValue: 'C:/LeosFastVideoEditor',
    );
    expect(
      clientId,
      isNotEmpty,
      reason: 'Use an ignored local --dart-define-from-file configuration.',
    );
    MediaKit.ensureInitialized(libmpv: '$root/third_party/mpv/libmpv-2.dll');
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('tiger-jamendo-live-'),
    ))!;
    final provider = JamendoProvider(clientId: clientId);
    final result = (await tester.runAsync(() => provider.searchPage('phonk')))!;
    expect(result.tracks, isNotEmpty);
    expect(result.tracks.first.previewUrl?.scheme, 'https');
    final key = GlobalKey();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 1000);
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xffc6f36a),
              brightness: Brightness.dark,
            ),
          ),
          home: JamendoMusicPage(
            provider: provider,
            configFile: File('${directory.path}/jamendo.json'),
            workingDirectory: directory,
            onUse: (_) async => fail('Editing is not approved'),
          ),
        ),
      ),
    );
    Future<void> settle() async {
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 80));
      }
    }

    Future<void> capture(String name) async {
      await settle();
      expect(tester.takeException(), isNull);
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      await tester.runAsync(
        () => File('$root/docs/$name').writeAsBytes(bytes.buffer.asUint8List()),
      );
      image.dispose();
    }

    try {
      await settle();
      await tester.tap(find.byKey(const ValueKey('jamendo-quick-phonk')));
      await settle();
      expect(find.text(result.tracks.first.title), findsOneWidget);
      await tester.tap(find.text(result.tracks.first.title));
      await settle();
      await capture('JAMENDO_DESKTOP.png');
      var heard = false;
      // A live catalogue can transiently omit fresh metadata. Retry only that
      // explicit service error; decoder/transport failures still fail this test.
      for (var attempt = 0; attempt < 3 && !heard; attempt++) {
        await tester.tap(find.byTooltip('Прослушать').first);
        for (var i = 0; i < 60 && !heard; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 500)),
          );
          await tester.pump(const Duration(milliseconds: 80));
          heard = find.byTooltip('Остановить').evaluate().isNotEmpty;
          if (find
              .textContaining('Jamendo не вернул сведения')
              .evaluate()
              .isNotEmpty)
            break;
        }
        if (!heard &&
            find
                .textContaining('Jamendo не вернул сведения')
                .evaluate()
                .isEmpty)
          break;
      }
      expect(
        heard,
        true,
        reason:
            'Production relay/player must reach a decoded positive audio position. '
            '${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? '').where((s) => s.contains('Не удалось') || s.contains('не поддерживает') || s.contains('не вернул сведения')).join('; ')}',
      );
      await tester.tap(find.byTooltip('Остановить').first);
      await settle();
      expect(find.byTooltip('Остановить'), findsNothing);
      tester.view.physicalSize = const Size(390, 844);
      await tester.binding.setSurfaceSize(const Size(390, 844));
      await capture('JAMENDO_PHONE.png');
      expect(
        directory
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.mp3') || f.path.endsWith('.part')),
        isEmpty,
        reason: 'Search and stream do not create downloaded music files.',
      );
      print(
        'JAMENDO_LIVE_PASS real API, production relay/MP3 decoder readiness/stop, desktop/phone UI, no audio files; editing gate remains closed.',
      );
    } finally {
      await tester.pumpWidget(const SizedBox());
      await settle();
      await tester.runAsync(() => directory.delete(recursive: true));
    }
  });
}
