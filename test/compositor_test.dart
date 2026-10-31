import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:tiger_video_edit/model.dart';
import 'package:tiger_video_edit/compositor.dart';

Future<List<int>> pixels(
  Still s, {
  int us = 0,
  List<Caption> captions = const [],
}) async {
  final r = ui.PictureRecorder();
  // generated source image has color detail so shake/blur can alter pixels
  final srcCanvas = ui.Canvas(r);
  srcCanvas.drawColor(const ui.Color(0xff224488), ui.BlendMode.src);
  srcCanvas.drawRect(
    const ui.Rect.fromLTWH(10, 10, 20, 20),
    ui.Paint()..color = const ui.Color(0xffff4422),
  );
  final pic = r.endRecording(), src = await pic.toImage(64, 64);
  final rec = ui.PictureRecorder();
  paintFrame(
    ui.Canvas(rec),
    const ui.Size(64, 64),
    src,
    s,
    localUs: us,
    sourceUs: us,
    captions: captions,
    referenceWidth: 64,
  );
  final outPic = rec.endRecording(), out = await outPic.toImage(64, 64);
  final data = await out.toByteData(format: ui.ImageByteFormat.rawRgba);
  final bytes = data!.buffer.asUint8List().toList();
  src.dispose();
  pic.dispose();
  out.dispose();
  outPic.dispose();
  return bytes;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'effect frame is deterministic and expires by configured duration',
    () async {
      final s = Still(
        path: 'x',
        effects: {'shake': .5, 'zoom': .3, 'flash': .4},
      );
      expect(await pixels(s, us: 100000), await pixels(s, us: 100000));
      expect(
        await pixels(s, us: 100000),
        isNot(await pixels(Still(path: 'x'), us: 100000)),
      );
      expect(
        await pixels(s, us: 500000),
        await pixels(Still(path: 'x'), us: 500000),
      );
    },
  );
  test('caption appears only in its half-open interval', () async {
    final s = Still(path: 'x'),
        captions = [
          Caption(
            id: 'a',
            text: 'T',
            startUs: 100000,
            endUs: 500000,
            fontSize: 24,
            x: .5,
            y: .5,
          ),
        ];
    expect(
      await pixels(s, us: 99999, captions: captions),
      await pixels(s, us: 99999),
    );
    expect(
      await pixels(s, us: 100000, captions: captions),
      isNot(await pixels(s, us: 100000)),
    );
    expect(
      await pixels(s, us: 500000, captions: captions),
      await pixels(s, us: 500000),
    );
  });
}
