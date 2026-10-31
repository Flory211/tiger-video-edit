import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:tiger_video_edit/platform_media.dart';
import 'package:tiger_video_edit/storage.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('export clean tutorial example with native system fonts', (
    tester,
  ) async {
    const root = String.fromEnvironment(
      'LEOS_ROOT',
      defaultValue: 'C:/LeosFastVideoEditor',
    );
    MediaKit.ensureInitialized(libmpv: '$root/third_party/mpv/libmpv-2.dll');
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Native tutorial export'))),
    );
    await tester.runAsync(() async {
      final project = await ProjectStore.read('$root/demo/Pulse-v2.tve');
      expect(project.captions.length, 2);
      expect(project.captions.any((c) => c.text == 'Мой первый эдит'), isFalse);
      final destination = '$root/tutorial/assets/result-example.mp4';
      await Directory('$root/tutorial/assets').create(recursive: true);
      var last = -1;
      await VideoExporter().export(project, destination, (value) {
        final percent = (value * 100).floor();
        if (percent ~/ 10 != last ~/ 10) {
          print('CLEAN_NATIVE_EXPORT $percent%');
          last = percent;
        }
      });
      expect(await File(destination).length(), greaterThan(100000));
      print('CLEAN_NATIVE_EXPORT_COMPLETE $destination');
    });
    await tester.pumpWidget(const SizedBox());
  }, timeout: const Timeout(Duration(minutes: 15)));
}
