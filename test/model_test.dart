import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tiger_video_edit/model.dart';

void main() {
  Project sample() => Project(
    name: 'Тест',
    audio: 'music.wav',
    durationUs: 10000000,
    endUs: 10000000,
    images: [
      Still(path: 'A'),
      Still(path: 'B'),
      Still(path: 'C'),
    ],
    markers: [
      Marker(id: 'a', timeUs: 2000000),
      Marker(id: 'b', timeUs: 4000000),
      Marker(id: 'c', timeUs: 6000000),
      Marker(id: 'd', timeUs: 8000000),
    ],
  );
  test('cycles A B C A B at exact frame boundaries', () {
    final p = sample();
    expect([0, 2000000, 4000000, 6000000, 8000000].map(p.imageIndexAt), [
      0,
      1,
      2,
      0,
      1,
    ]);
    expect(p.imageIndexAt(1999999), 0);
    expect(p.segments.map((s) => s.frameCount), [60, 60, 60, 60, 60]);
  });
  test('no markers uses first image, extra images unused', () {
    final p = sample().copy(markers: []);
    expect(p.imageIndexAt(9000000), 0);
    expect(p.segments.length, 1);
  });
  test('trim boundaries excluded; source times retained', () {
    final p = sample().copy(startUs: 2000000, endUs: 8000000);
    expect(p.segments.map((s) => s.imageIndex), [0, 1, 2]);
    expect(p.imageIndexAt(2000000), 0);
    expect(p.imageIndexAt(4000000), 1);
    expect(p.totalFrames, 180);
  });
  test('duplicate and subframe markers never create empty segments', () {
    final p = sample().copy(
      markers: [
        Marker(id: 'a', timeUs: 1000001),
        Marker(id: 'b', timeUs: 1000001),
        Marker(id: 'c', timeUs: 1000002),
      ],
    );
    expect(p.segments.every((s) => s.frameCount > 0), isTrue);
    expect(p.segments.map((s) => s.imageIndex), [0, 2]);
    expect(p.imageIndexAt(1000002), 0);
    expect(p.imageIndexAt(1033334), 2);
  });
  test('microsecond times survive JSON roundtrip', () {
    final p = sample().copy(markers: [Marker(id: 'a', timeUs: 1234567)]);
    final q = Project.fromJson(jsonDecode(jsonEncode(p.toJson())));
    expect(q.markers.single.timeUs, 1234567);
    expect(q.toJson(), p.toJson());
  });
  test('frame schedule and preview agree at every output frame', () {
    final p = sample().copy(markers: [Marker(id: 'a', timeUs: 1234567)]);
    for (final s in p.segments) {
      for (var f = s.startFrame; f < s.startFrame + s.frameCount; f++) {
        expect(
          p.imageIndexAt(p.startUs + (f * 1000000 / 30).ceil()),
          s.imageIndex,
        );
      }
    }
  });
  test('invalid schema and trim are rejected', () {
    expect(() => Project.fromJson({'version': 999}), throwsFormatException);
    expect(() => sample().copy(endUs: 0).validate(), throwsFormatException);
  });
  test('history restores edits and invalidates redo after new edit', () {
    final h = ProjectHistory(sample());
    h.change(h.current.copy(markers: []));
    h.undo();
    expect(h.current.markers.length, 4);
    h.redo();
    expect(h.current.markers, isEmpty);
    h.undo();
    h.change(h.current.copy(name: 'new'));
    expect(h.canRedo, isFalse);
  });
}
