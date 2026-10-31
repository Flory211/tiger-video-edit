// ignore_for_file: avoid_print
import 'package:tiger_video_edit/model.dart';

void main() {
  final p = Project(
    audio: 'test.wav',
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
    ],
  );
  if (p.imageIndexAt(2000000) != 1) throw StateError('At 2s expected B');
  if (p.segments.length != 4) throw StateError('Expected four segments');
  print('Timeline check passed');
}

