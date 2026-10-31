import 'package:flutter_test/flutter_test.dart';
import 'package:tiger_video_edit/audio_clip.dart';

void main() {
  test('source-time audio envelope and half-open bounds', () {
    const clip = AudioClip(
      id: 'a',
      path: 'tone.wav',
      startUs: 1000000,
      durationUs: 2000000,
      fadeInUs: 500000,
      fadeOutUs: 500000,
      volume: .8,
    );
    expect(clip.gainAt(999999), 0);
    expect(clip.gainAt(1000000), 0);
    expect(clip.gainAt(1250000), closeTo(.4, .00001));
    expect(clip.gainAt(2000000), .8);
    expect(clip.gainAt(2750000), closeTo(.4, .00001));
    expect(clip.gainAt(3000000), 0);
    expect(AudioClip.fromJson(clip.toJson()).toJson(), clip.toJson());
  });
  test('invalid and disabled clips cannot leak audible output', () {
    const clip = AudioClip(id: 'a', path: 'tone.wav', durationUs: 1000000);
    expect(clip.copy(enabled: false).gainAt(500000), 0);
    expect(
      () => clip.copy(volume: double.nan).validate(),
      throwsFormatException,
    );
    expect(
      () => clip.copy(fadeInUs: 2000000).validate(),
      throwsFormatException,
    );
    expect(() => clip.copy(track: -1).validate(), throwsFormatException);
    expect(() => clip.copy(durationUs: 0).validate(), throwsFormatException);
  });
}
