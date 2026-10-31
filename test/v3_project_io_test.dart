import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tiger_video_edit/model.dart';
import 'package:tiger_video_edit/editor.dart';
import 'package:tiger_video_edit/storage.dart';

import 'editor_test.dart' show DeviceAudio;

void main() {
  test(
    'recovery replaces every additional audio and visual reference',
    () async {
      final dir = await Directory.systemTemp.createTemp('tve_v3_relink_');
      final e = Editor(
        LocalLibrary(dir),
        DeviceAudio(),
        probeFactory: () => DeviceAudio(),
      );
      try {
        final missingAudio = '${dir.path}/moved.wav',
            missingImage = '${dir.path}/moved.png';
        e.change(
          Project(
            audioClips: [
              AudioClip(id: 'a', path: missingAudio, durationUs: 1000000),
            ],
            visualClips: [
              VisualClip(
                id: 'v',
                media: Still(path: missingImage),
                startUs: 0,
                durationUs: 1000000,
              ),
            ],
          ),
        );
        expect(
          e.project.mediaReferences,
          containsAll([missingAudio, missingImage]),
        );
        await e.relink(
          missingAudio,
          '${Directory.current.path}/demo/pulse.wav',
        );
        await e.relink(
          missingImage,
          '${Directory.current.path}/demo/frame1.png',
        );
        expect(await ProjectStore.missing(e.project), isEmpty);
        expect(e.project.audioClips.single.id, 'a');
        expect(e.project.visualClips.single.id, 'v');
        expect(
          e.project.audioClips.single.path.replaceAll('\\', '/'),
          startsWith('${dir.path}/media'.replaceAll('\\', '/')),
        );
      } finally {
        e.dispose();
        await dir.delete(recursive: true);
      }
    },
  );
  test('additional music is an editable independent track rather than replacing the main song', () async {
    final dir = await Directory.systemTemp.createTemp('tve_v3_music_layer_');
    final e = Editor(LocalLibrary(dir), DeviceAudio());
    try {
      e.change(Project(audio: 'main.wav', durationUs: 3000000, endUs: 3000000));
      e.positionUs = 1000000;
      e.addAudioLayer('voice.wav', 1500000);
      e.addAudioLayer('instrument.wav', 3000000);
      expect(e.project.audio, 'main.wav');
      expect(e.project.audioClips.map((c) => c.track), [0, 1]);
      expect(e.project.audioClips.last.endUs, 3000000);
      expect(e.project.audioClips.first.group, 'music');
      await e.undo();
      expect(e.project.audioClips.length, 1);
    } finally {
      e.dispose();
      await dir.delete(recursive: true);
    }
  });
  test(
    'frame rate resolution and independent media references survive safe save',
    () async {
      final dir = await Directory.systemTemp.createTemp('tve_v3_io_');
      try {
        for (final rate in [24, 30, 60]) {
          final p = Project(
            audio: 'music.wav',
            durationUs: 2000000,
            startUs: 500000,
            endUs: 1500000,
            frameRate: rate,
            resolution: 720,
            images: [const Still(path: 'image.png')],
            audioClips: [
              const AudioClip(
                id: 'a',
                path: 'pop.wav',
                startUs: 750000,
                durationUs: 250000,
              ),
            ],
            visualClips: [
              const VisualClip(
                id: 'v',
                media: Still(path: 'clip.mp4'),
                startUs: 500000,
                durationUs: 500000,
              ),
            ],
          );
          final path = '${dir.path}/rate_$rate.tve';
          await ProjectStore.save(path, p);
          final read = await ProjectStore.read(path);
          expect(read.totalFrames, rate);
          expect(read.width, 1280);
          expect(read.height, 720);
          expect(
            read.audioClips.single.path,
            File('${dir.path}/pop.wav').absolute.path,
          );
          expect(
            read.visualClips.single.media.path,
            File('${dir.path}/clip.mp4').absolute.path,
          );
          final bytes = await File(path).readAsBytes();
          await ProjectStore.read(path);
          expect(await File(path).readAsBytes(), bytes);
        }
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'concurrent track bound is explicit and uses half-open clip intervals',
    () {
      final clips = [
        for (var i = 0; i < 16; i++)
          AudioClip(
            id: 's$i',
            path: 'sound.wav',
            startUs: 0,
            durationUs: 1000000,
          ),
      ];
      final p = Project(audioClips: clips);
      expect(p.validate, returnsNormally);
      expect(
        p
            .copy(
              audioClips: [
                ...clips,
                const AudioClip(
                  id: 'extra',
                  path: 'sound.wav',
                  durationUs: 1000000,
                ),
              ],
            )
            .validate,
        throwsFormatException,
      );
      expect(
        p
            .copy(
              audioClips: [
                ...clips,
                const AudioClip(
                  id: 'next',
                  path: 'sound.wav',
                  startUs: 1000000,
                  durationUs: 1000000,
                ),
              ],
            )
            .validate,
        returnsNormally,
      );
    },
  );
  test('old malformed preferences and backup do not brick startup or rewrite originals', () async {
    final dir = await Directory.systemTemp.createTemp('tve_v3_prefs_');
    final e = Editor(LocalLibrary(dir), DeviceAudio());
    try {
      final source = File('${dir.path}/settings.json');
      await source.writeAsString('{bad');
      await File('${source.path}.bak').writeAsString(
        '{"presets":"bad","markerKey":123,"countdown":false,"recent":{},"autosaveSeconds":"bad"}',
      );
      await e.initialize();
      expect(e.markerKey, 'G');
      expect(e.countdown, false);
      expect(e.autosaveSeconds, 60);
      expect(await source.readAsString(), '{bad');
    } finally {
      e.dispose();
      await dir.delete(recursive: true);
    }
  });
  test('dragging a marker never snaps back to the marker itself', () async {
    final dir = await Directory.systemTemp.createTemp('tve_v3_snap_');
    final e = Editor(LocalLibrary(dir), DeviceAudio());
    try {
      e.change(
        Project(
          audio: 'source.wav',
          durationUs: 3000000,
          endUs: 3000000,
          markers: [
            const Marker(id: 'moving', timeUs: 1000000),
            const Marker(id: 'target', timeUs: 1500000),
          ],
        ),
      );
      expect(e.snapTime(1030000, excludeMarkerId: 'moving'), 1030000);
      expect(e.snapTime(1460000, excludeMarkerId: 'moving'), 1500000);
    } finally {
      e.dispose();
      await dir.delete(recursive: true);
    }
  });
}
