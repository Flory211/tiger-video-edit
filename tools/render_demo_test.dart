import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tiger_video_edit/platform_media.dart';
import 'package:tiger_video_edit/storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('render original demo MP4', () async {
    final root = Directory.current.path;
    final project = await ProjectStore.read('$root/demo/Pulse.tve');
    await VideoExporter().export(project, '$root/demo/Pulse.mp4', (_) {});
    await validateVideo('$root/demo/Pulse.mp4', 10);
    expect(await File('$root/demo/Pulse.mp4').length(), greaterThan(100));
  }, timeout: const Timeout(Duration(minutes: 4)));
}
