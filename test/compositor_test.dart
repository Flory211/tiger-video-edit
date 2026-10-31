import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:tiger_video_edit/model.dart';
import 'package:tiger_video_edit/compositor.dart';

Future<List<int>> pixels(
  Still s, {
  int us = 0,
  List<Caption> captions = const [],
  Project? project,
  bool withPrevious = false,
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
  final prevRec = ui.PictureRecorder();
  ui.Canvas(prevRec).drawColor(const ui.Color(0xff55ff11), ui.BlendMode.src);
  final prevPic = prevRec.endRecording(), prev = await prevPic.toImage(64, 64);
  final rec = ui.PictureRecorder();
  paintFrame(
    ui.Canvas(rec),
    const ui.Size(64, 64),
    src,
    s,
    localUs: us,
    sourceUs: us,
    captions: captions,
    project: project,
    previousImage: withPrevious ? prev : null,
    referenceWidth: 64,
  );
  final outPic = rec.endRecording(), out = await outPic.toImage(64, 64);
  final data = await out.toByteData(format: ui.ImageByteFormat.rawRgba);
  final bytes = data!.buffer.asUint8List().toList();
  prev.dispose();
  prevPic.dispose();
  src.dispose();
  pic.dispose();
  out.dispose();
  outPic.dispose();
  return bytes;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('every published effect changes pixels and is deterministic', () async {
    final plain = await pixels(const Still(path: 'x'), us: 100000);
    for (final type in supportedEffectTypes) {
      final s = Still(
        path: 'x',
        effectStack: [EffectInstance(id: 'e', type: type, strength: .8)],
      );
      final actual = await pixels(s, us: 100000, withPrevious: true);
      expect(actual, isNot(plain), reason: type);
      expect(
        actual,
        await pixels(s, us: 100000, withPrevious: true),
        reason: type,
      );
      expect(
        await pixels(s, us: 500000, withPrevious: true),
        await pixels(const Still(path: 'x'), us: 500000),
        reason: type,
      );
    }
  });
  test(
    'global layer wraps captions and global switch restores original',
    () async {
      const s = Still(path: 'x');
      const captions = [
        Caption(
          id: 'c',
          text: 'T',
          startUs: 0,
          endUs: 1000000,
          fontSize: 30,
          x: .5,
          y: .5,
        ),
      ];
      final p = Project(
        durationUs: 1000000,
        endUs: 1000000,
        images: [s],
        globalEffects: [
          GlobalAdjustmentLayer(
            id: 'l',
            effects: [EffectInstance(id: 'f', type: 'flash', strength: 1)],
          ),
        ],
      );
      final plain = await pixels(s, us: 100000, captions: captions);
      expect(
        await pixels(s, us: 100000, captions: captions, project: p),
        isNot(plain),
      );
      expect(
        await pixels(
          s,
          us: 100000,
          captions: captions,
          project: p.copy(globalEffectsEnabled: false),
        ),
        plain,
      );
      expect(
        await pixels(
          s,
          us: 100000,
          captions: captions,
          project: p.copy(
            globalEffects: [p.globalEffects.first.copy(enabled: false)],
          ),
        ),
        plain,
      );
    },
  );
  test('global full flash covers caption pixels and always holds end level', () async {
    const s = Still(path: 'x');
    const captions = [
      Caption(
        id: 'c',
        text: 'T',
        startUs: 0,
        endUs: 2000000,
        fontSize: 30,
        x: .5,
        y: .5,
      ),
    ];
    final p = Project(
      durationUs: 2000000,
      endUs: 2000000,
      images: [s],
      globalEffects: [
        GlobalAdjustmentLayer(
          id: 'l',
          effects: [
            EffectInstance(
              id: 'f',
              type: 'flash',
              strength: 1,
              beginIntensity: 1,
              endIntensity: 1,
            ),
          ],
        ),
      ],
    );
    final actual = await pixels(s, us: 1000000, captions: captions, project: p);
    expect(actual, isNot(await pixels(s, us: 1000000, captions: captions)));
    // White overlay must also increase the dark shadow pixels around the text.
    final plain = await pixels(s, us: 1000000, captions: captions);
    for (var i = 0; i < actual.length; i += 4) {
      expect(actual[i], greaterThanOrEqualTo(plain[i]));
      expect(actual[i + 1], greaterThanOrEqualTo(plain[i + 1]));
      expect(actual[i + 2], greaterThanOrEqualTo(plain[i + 2]));
    }
  });
  test('ordered effects differ and animation persists at final key', () async {
    const zoom = EffectInstance(id: 'z', type: 'zoom', strength: 1),
        pan = EffectInstance(id: 'p', type: 'pan', strength: 1);
    expect(
      await pixels(
        const Still(path: 'x', effectStack: [zoom, pan]),
        us: 100000,
      ),
      isNot(
        await pixels(
          const Still(path: 'x', effectStack: [pan, zoom]),
          us: 100000,
        ),
      ),
    );
    final s = Still(
      path: 'x',
      animations: [
        AnimationTrack(
          id: 'a',
          property: AnimationProperty.x,
          keyframes: [
            Keyframe(timeUs: 0, value: 0),
            Keyframe(timeUs: 100000, value: .3),
          ],
        ),
      ],
    );
    expect(
      await pixels(s, us: 500000),
      isNot(await pixels(const Still(path: 'x'), us: 500000)),
    );
  });
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
