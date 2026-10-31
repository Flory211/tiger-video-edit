import 'package:flutter_test/flutter_test.dart';
import 'package:tiger_video_edit/model.dart';

void main() {
  test('v2 saves effects captions and clip trim while v1 still loads', () {
    final p = Project(
      audio: 'a.wav',
      durationUs: 2000000,
      endUs: 2000000,
      images: [
        Still(
          path: 'clip.mp4',
          effects: {'shake': .4},
          sourceStartUs: 100000,
          durationUs: 3000000,
        ),
      ],
      captions: [Caption(id: 'a', text: 'Tiger', startUs: 0, endUs: 1000000)],
    );
    final json = p.toJson();
    expect(json['version'], 3);
    final q = Project.fromJson(json);
    expect(q.images.single.kind, 'video');
    expect(q.images.single.effects['shake'], .4);
    expect(q.captions.single.text, 'Tiger');
    final old = Project().toJson()
      ..['version'] = 1
      ..remove('captions');
    expect(Project.fromJson(old).captions, isEmpty);
  });
  test('v2 rejects nonfinite effects and invalid caption ranges', () {
    final p = Project(
      images: [
        Still(path: 'a', effects: {'shake': double.nan}),
      ],
    );
    expect(p.validate, throwsFormatException);
    expect(
      Project(
        captions: [Caption(id: 'a', text: 'bad', startUs: 10, endUs: 1)],
      ).validate,
      throwsFormatException,
    );
  });
}
