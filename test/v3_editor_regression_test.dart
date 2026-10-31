import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:tiger_video_edit/app_settings.dart';
import 'package:tiger_video_edit/beat.dart';
import 'package:tiger_video_edit/edit_templates.dart';
import 'package:tiger_video_edit/editor.dart';
import 'package:tiger_video_edit/model.dart';
import 'package:tiger_video_edit/platform_media.dart';
import 'package:tiger_video_edit/storage.dart';

class _Streams extends Fake implements PlayerStream {
  @override
  Stream<String> get error => const Stream.empty();
}

class _Player extends Fake implements Player {
  double volume = 100;
  @override
  PlayerStream get stream => _Streams();
  @override
  Future<void> pause() async {}
  @override
  Future<void> setVolume(double value) async {
    volume = value;
  }

  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> dispose() async {}
}

class _Audio extends Fake implements AudioEngine {
  @override
  final _Player player = _Player();
  @override
  Future<int> open(String path) async => 10000000;
  @override
  Future<int> positionUs() async => 0;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late Editor editor;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('tve-regression-');
    editor = Editor(LocalLibrary(root), _Audio());
  });
  tearDown(() async {
    editor.dispose();
    await root.delete(recursive: true);
  });
  Project mediaProject({List<Still>? images}) => Project(
    audio: File('demo/pulse.wav').absolute.path,
    durationUs: 10000000,
    endUs: 10000000,
    images:
        images ??
        [const Still(path: 'first.png'), const Still(path: 'second.png')],
  );
  const template = EditTemplate(
    id: 'test',
    name: 'Test',
    effects: [EffectInstance(id: 'zoom', type: 'zoom', strength: .3)],
  );

  test('new project clears grouped selection and pending template', () async {
    editor.change(Project(images: [const Still(path: 'old.png')]));
    editor.selectAllImages();
    await editor.applyTemplate(template);
    await editor.newProject('Fresh');
    expect(editor.selectedImages, isEmpty);
    expect(editor.pendingTemplate, isNull);
    expect(editor.dirty, false);
  });

  test('opening a different project clears grouped selection without rewriting source', () async {
    editor.change(Project(images: [const Still(path: 'old.png')]));
    editor.selectAllImages();
    final source = File('${root.path}/opened.tve');
    await ProjectStore.save(
      source.path,
      Project(
        name: 'Opened',
        images: [const Still(path: 'new.png')],
      ),
    );
    final bytes = await source.readAsBytes();
    await editor.openProject(source.path);
    expect(editor.selectedImages, isEmpty);
    expect(editor.project.name, 'Opened');
    expect(await source.readAsBytes(), bytes);
  });

  test('legacy copy and paste transfers visible effects and duration only to selected images', () {
    editor.change(
      Project(
        images: [
          const Still(
            path: 'a.png',
            effects: {'glow': .7},
            effectDurationUs: 900000,
          ),
          const Still(path: 'b.png'),
          const Still(path: 'c.png'),
        ],
      ),
    );
    editor.selectImage(0);
    editor.copyEffects();
    editor.selectImage(1);
    editor.pasteEffects();
    expect(editor.project.images[1].effects, {'glow': .7});
    expect(editor.project.images[1].effectDurationUs, 900000);
    expect(editor.project.images[2].effects, isEmpty);
  });

  test('copying an empty effect stack clears effects on paste', () {
    editor.change(
      Project(
        images: [
          const Still(path: 'empty.png'),
          const Still(
            path: 'decorated.png',
            effects: {'flash': .4},
            effectStack: [EffectInstance(id: 'shake', type: 'shake')],
          ),
        ],
      ),
    );
    editor.selectImage(0);
    editor.copyEffects();
    editor.selectImage(1);
    editor.pasteEffects();
    expect(editor.project.images[1].effects, isEmpty);
    expect(editor.project.images[1].effectStack, isEmpty);
  });

  test(
    'pending template applies when audio is imported after images',
    () async {
      await editor.applyTemplate(template);
      await editor.useMediaPaths([File('demo/frame1.png').absolute.path]);
      expect(editor.pendingTemplate, isNotNull);
      await editor.useAudioPath(File('demo/pulse.wav').absolute.path);
      expect(editor.pendingTemplate, isNull);
      expect(editor.project.images.single.effectStack.single.type, 'zoom');
      expect(await File(editor.project.images.single.path).exists(), true);
    },
  );

  test(
    'pending template applies when images are imported after audio',
    () async {
      await editor.applyTemplate(template);
      await editor.useAudioPath(File('demo/pulse.wav').absolute.path);
      expect(editor.pendingTemplate, isNotNull);
      await editor.useMediaPaths([File('demo/frame1.png').absolute.path]);
      expect(editor.pendingTemplate, isNull);
      expect(editor.project.images.single.effectStack.single.type, 'zoom');
    },
  );

  test(
    'reused template does not keep marker IDs from source project',
    () async {
      editor.change(mediaProject());
      editor.beatAnalysis = BeatAnalysis(timesUs: [1000000, 2000000]);
      await editor.applyTemplate(
        const EditTemplate(
          id: 'reused',
          name: 'Reused',
          globalEffects: [
            GlobalAdjustmentLayer(
              id: 'global',
              mode: GlobalEffectMode.selectedMarkers,
              markerIds: ['source-project-marker'],
              effects: [EffectInstance(id: 'flash', type: 'flash')],
            ),
          ],
        ),
      );
      expect(
        editor.project.globalEffects.single.mode,
        GlobalEffectMode.everyMarker,
      );
      expect(editor.project.globalEffects.single.markerIds, isEmpty);
      editor.project.validate();
    },
  );

  test('rapid settings saves persist the last choice and new projects use export defaults', () async {
    final first = const AppSettings().copyWith(
      previewVolume: .2,
      exportFps: 24,
      exportHeight: 720,
    );
    final last = first.copyWith(
      previewVolume: .6,
      exportQuality: ExportQuality.maximum,
    );
    await Future.wait([
      editor.updateSettings(first),
      editor.updateSettings(last),
    ]);
    final saved = await SettingsStore(File('${root.path}/app_settings.json'))
        .load();
    expect(saved.previewVolume, .6);
    expect(editor.settings.previewVolume, .6);
    await editor.newProject('Defaults');
    expect(editor.project.frameRate, 24);
    expect(editor.project.height, 720);
    editor.project.validate();
  });

  test('copying a sound ending at project end remains audible inside trim', () {
    const clip = AudioClip(
      id: 'last',
      path: 'last.wav',
      startUs: 9000000,
      durationUs: 1000000,
    );
    editor.change(mediaProject().copy(audioClips: [clip]));
    editor.duplicateAudioClip(clip);
    final duplicate = editor.project.audioClips.last;
    expect(duplicate.id, isNot(clip.id));
    expect(duplicate.startUs, lessThan(editor.project.endUs));
    expect(duplicate.endUs, lessThanOrEqualTo(editor.project.endUs));
    expect(duplicate.gainAt(duplicate.startUs + 500000), greaterThan(0));
  });
  test(
    'copy at audio limit reports an error without destroying existing clips',
    () {
      final clips = [
        for (var i = 0; i < 1024; i++)
          AudioClip(
            id: 'clip_$i',
            path: 'sound.wav',
            startUs: 1000000 + i * 2000,
            durationUs: 1000,
          ),
      ];
      editor.change(mediaProject().copy(audioClips: clips));
      expect(() => editor.duplicateAudioClip(clips.first), returnsNormally);
      expect(editor.project.audioClips.length, 1024);
      expect(editor.error, isNotNull);
    },
  );
}
