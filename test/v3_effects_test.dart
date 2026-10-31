import 'package:tiger_video_edit/effect_recipes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiger_video_edit/model.dart';

void main() {
  test('29 named recipes contain validated editable primitives', () {
    expect(effectRecipes.length, 29);
    expect(effectRecipes.map((r) => r.name).toSet().length, 29);
    for (final recipe in effectRecipes) {
      expect(recipe.effects, isNotEmpty, reason: recipe.name);
      validateEffects(recipe.effects);
      if (recipe.category == 'Transitions') {
        expect(recipe.needsPreviousImage, isTrue, reason: recipe.name);
      }
    }
  });
  test(
    'audio clips and group levels survive project copy and serialization',
    () {
      final p = Project(
        durationUs: 1000000,
        endUs: 1000000,
        audioClips: [
          const AudioClip(id: 'a', path: 'a.wav', durationUs: 500000),
        ],
        musicVolume: .5,
        soundVolume: 1.5,
      );
      final q = Project.fromJson(p.copy(name: 'saved').toJson());
      expect(q.audioClips.single.path, 'a.wav');
      expect(q.musicVolume, .5);
      expect(q.soundVolume, 1.5);
      expect(
        () => p.copy(musicVolume: double.nan).validate(),
        throwsFormatException,
      );
      expect(
        () => p
            .copy(audioClips: [p.audioClips.single, p.audioClips.single])
            .validate(),
        throwsFormatException,
      );
    },
  );

  test('interpolation endpoints, overshoot and Bezier midpoint', () {
    for (final curve in Interpolation.values) {
      final t = AnimationTrack(
        id: 'a',
        property: AnimationProperty.scale,
        keyframes: [
          Keyframe(
            timeUs: 0,
            value: 1,
            interpolation: curve,
            bezier: const [0, 0, 1, 1],
          ),
          const Keyframe(timeUs: 1000000, value: 2),
        ],
      );
      expect(t.evaluate(-1), 1);
      expect(t.evaluate(1000001), 2);
      expect(t.evaluate(500000).isFinite, isTrue);
    }
    expect(
      interpolateCurve(.5, Interpolation.cubicBezier, [0, 0, 1, 1]),
      closeTo(.5, .001),
    );
    expect(
      interpolateCurve(.8, Interpolation.back, [0, 0, 1, 1]),
      greaterThan(1),
    );
  });
  test('effect envelope honors delay, strength, frequency and disabled', () {
    const e = EffectInstance(
      id: 'e',
      type: 'zoom',
      delayUs: 100000,
      durationUs: 1000000,
      strength: .8,
      beginIntensity: 1,
      endIntensity: .5,
    );
    expect(e.amountAt(99999), 0);
    expect(e.amountAt(100000), .8);
    expect(e.amountAt(600000), closeTo(.6, .0001));
    expect(e.amountAt(1100000), 0);
    expect(e.amountAt(2100000, holdLast: true), .4);
    expect(e.copy(enabled: false).amountAt(100000), 0);
    expect(e.copy(frequency: 1).amountAt(600000), closeTo(0, .0001));
  });
  test(
    'all global trigger modes use latest appropriate absolute source time',
    () {
      final markers = [
        const MapEntry('a', 200000),
        const MapEntry('b', 400000),
      ];
      int? at(GlobalEffectMode mode, int us, {List<String> ids = const []}) =>
          GlobalAdjustmentLayer(
            id: 'l',
            mode: mode,
            startUs: 150000,
            endUs: 600000,
            markerIds: ids,
          ).localTime(
            us,
            projectStartUs: 100000,
            markers: markers,
            imageChanges: [100000, 300000],
          );
      expect(at(GlobalEffectMode.always, 500000), 400000);
      expect(at(GlobalEffectMode.range, 149999), isNull);
      expect(at(GlobalEffectMode.range, 600000), isNull);
      expect(at(GlobalEffectMode.range, 200000), 50000);
      expect(at(GlobalEffectMode.everyMarker, 199999), isNull);
      expect(at(GlobalEffectMode.everyMarker, 450000), 50000);
      expect(at(GlobalEffectMode.selectedMarkers, 450000, ids: ['a']), 250000);
      expect(at(GlobalEffectMode.imageChanges, 450000), 150000);
    },
  );
  test('validation rejects nonfinite, duplicate IDs, unsorted keys, and future schemas', () {
    expect(
      () => const EffectInstance(
        id: 'e',
        type: 'zoom',
        strength: double.nan,
      ).validate(),
      throwsFormatException,
    );
    expect(
      () => const EffectInstance(id: 'e', type: 'fake').validate(),
      throwsFormatException,
    );
    expect(
      () => validateEffects([
        const EffectInstance(id: 'e', type: 'zoom'),
        const EffectInstance(id: 'e', type: 'blur'),
      ]),
      throwsFormatException,
    );
    expect(
      () => const AnimationTrack(
        id: 'a',
        property: AnimationProperty.x,
        keyframes: [
          Keyframe(timeUs: 5, value: 0),
          Keyframe(timeUs: 4, value: 1),
        ],
      ).validate(),
      throwsFormatException,
    );
    final j = Project().toJson();
    j['version'] = 4;
    expect(() => Project.fromJson(j), throwsFormatException);
  });
  test('v1 and v2 migrate without mutating original legacy maps', () {
    for (final version in [1, 2]) {
      final j = Project(
        images: [
          const Still(path: 'x', effects: {'shake': .5}),
        ],
      ).toJson();
      j['version'] = version;
      j.remove('globalEffects');
      j.remove('globalEffectsEnabled');
      final original = j.toString();
      final p = Project.fromJson(j);
      expect(p.images.first.effects, {'shake': .5});
      expect(p.images.first.effectStack, isEmpty);
      expect(p.globalEffectsEnabled, isTrue);
      expect(j.toString(), original);
    }
  });

  test('v3 data survives round trip and enables frame rendering', () {
    final j = Project(
      durationUs: 1000000,
      endUs: 1000000,
      images: [Still(path: 'x')],
    ).toJson();
    j['version'] = 3;
    (j['images'] as List)[0]['effectStack'] = [
      {'id': 'e', 'type': 'zoom', 'strength': .7},
    ];
    final p = Project.fromJson(j);
    expect(p.toJson()['version'], 3);
    expect((p.toJson()['images'] as List)[0]['effectStack'], isNotEmpty);
    expect(p.needsFrameRendering, isTrue);
  });
}
