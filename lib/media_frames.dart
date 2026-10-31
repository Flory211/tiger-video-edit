import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'media_bridge.dart';
import 'model.dart';

class MediaInfo {
  final int durationUs, width, height;
  const MediaInfo({
    required this.durationUs,
    required this.width,
    required this.height,
  });
}

Future<MediaInfo> inspectMedia(String path) async {
  if (!await File(path).exists()) {
    throw FileSystemException('Media does not exist', path);
  }
  final kind = Still(path: path).kind;
  if (kind == 'video') {
    if (Platform.isAndroid) {
      final m = await nativeMedia.invokeMapMethod<String, dynamic>(
        'inspectVideo',
        {'path': path},
      );
      return MediaInfo(
        durationUs: (m!['durationUs'] as num).toInt(),
        width: (m['width'] as num).toInt(),
        height: (m['height'] as num).toInt(),
      );
    }
    final result = await Process.run(mediaTool('ffprobe'), [
      '-v',
      'error',
      '-select_streams',
      'v:0',
      '-show_entries',
      'stream=width,height,duration:stream_tags=rotate:stream_side_data=rotation:format=duration',
      '-of',
      'json',
      path,
    ]);
    if (result.exitCode != 0) {
      throw FormatException('Cannot inspect video: ${result.stderr}');
    }
    final m = jsonDecode(result.stdout as String) as Map<String, dynamic>;
    final stream = (m['streams'] as List).first as Map<String, dynamic>;
    final seconds =
        double.tryParse('${stream['duration']}') ??
        double.tryParse('${m['format']?['duration']}') ??
        0;
    final width = (stream['width'] as num).toInt(),
        height = (stream['height'] as num).toInt();
    var rotation = double.tryParse('${stream['tags']?['rotate']}') ?? 0;
    for (final sideData in (stream['side_data_list'] as List? ?? const [])) {
      if (sideData['rotation'] != null) {
        rotation = (sideData['rotation'] as num).toDouble();
        break;
      }
    }
    // FFmpeg autorotates before scaling, so use the displayed aspect ratio.
    final swap = rotation.round() % 180 == 90;
    if (width <= 0 || height <= 0 || seconds <= 0) {
      throw const FormatException('Invalid video metadata');
    }
    return MediaInfo(
      durationUs: (seconds * 1000000).round(),
      width: swap ? height : width,
      height: swap ? width : height,
    );
  }
  final codec = await ui.instantiateImageCodec(
    await File(path).readAsBytes(),
    targetWidth: 1,
  );
  // Read full dimensions separately: the metadata scan itself uses tiny frames.
  final buffer = await ui.ImmutableBuffer.fromFilePath(path);
  final descriptor = await ui.ImageDescriptor.encoded(buffer);
  try {
    var duration = 0;
    if (kind == 'gif') {
      for (var i = 0; i < codec.frameCount; i++) {
        final frame = await codec.getNextFrame();
        duration += math.max(10000, frame.duration.inMicroseconds);
        frame.image.dispose();
      }
    }
    return MediaInfo(
      durationUs: duration,
      width: descriptor.width,
      height: descriptor.height,
    );
  } finally {
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
  }
}

/// One active animated decoder, one retained frame. Every returned image is a clone
/// owned by its caller. Calls are serialized so preview and export may share it.
class MediaFrameSource {
  final int maxDimension;
  MediaFrameSource({this.maxDimension = 1920}) {
    if (maxDimension <= 0) throw ArgumentError.value(maxDimension);
  }
  Future<void> _pending = Future.value();
  bool _disposed = false;
  String? _path;
  MediaInfo? _info;
  ui.Codec? _codec;
  ui.Image? _image;
  int _gifStart = 0, _gifEnd = 0, _gifIndex = -1;
  Process? _process;
  StreamIterator<List<int>>? _bytes;
  List<int> _chunk = const [];
  int _chunkAt = 0, _videoIndex = -1, _videoAnchor = -1;
  int _width = 0, _height = 0;

  Future<ui.Image> frame(Still item, int localUs) {
    final result = _pending.then((_) => _frame(item, localUs));
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<ui.Image> _frame(Still item, int localUs) async {
    if (_disposed) throw StateError('Frame source is disposed');
    if (_path != item.path) {
      await _reset();
      final info = await inspectMedia(item.path);
      _info = info;
      _path = item.path;
      final scale = math.min(
        1.0,
        maxDimension / math.max(info.width, info.height),
      );
      _width = math.max(1, (info.width * scale).round());
      _height = math.max(1, (info.height * scale).round());
    }
    final duration = item.durationUs > 0 ? item.durationUs : _info!.durationUs;
    final time = duration > 0 ? (item.sourceStartUs + localUs) % duration : 0;
    if (item.kind == 'video') {
      if (Platform.isAndroid) {
        final bytes = await nativeMedia.invokeMethod<Uint8List>('videoFrame', {
          'path': item.path,
          'timeUs': time,
          'maxDimension': maxDimension,
        });
        final codec = await ui.instantiateImageCodec(bytes!);
        try {
          return (await codec.getNextFrame()).image;
        } finally {
          codec.dispose();
        }
      }
      // Use fixed one-second anchors so all access paths share the same fps
      // resampling phase. At most 29 output frames are discarded per request;
      // FFmpeg input seeking can still decode from an earlier codec keyframe.
      final index = time * 30 ~/ 1000000;
      final anchor = index ~/ 30 * 30;
      if (_process == null || anchor != _videoAnchor || index < _videoIndex) {
        await _stopVideo();
        _videoAnchor = anchor;
        _videoIndex = anchor - 1;
        final process = await Process.start(mediaTool('ffmpeg'), [
          '-v',
          'error',
          '-ss',
          (anchor ~/ 30).toString(),
          '-i',
          item.path,
          '-an',
          '-sn',
          '-vf',
          'fps=30:eof_action=pass,scale=$_width:$_height',
          '-pix_fmt',
          'rgba',
          '-f',
          'rawvideo',
          'pipe:1',
        ]);
        _process = process;
        process.stderr.drain<void>();
        _bytes = StreamIterator(process.stdout);
      }
      while (_videoIndex < index) {
        final pixels = await _readPixels(_width * _height * 4);
        _videoIndex++;
        if (_videoIndex != index) continue;
        final completer = Completer<ui.Image>();
        ui.decodeImageFromPixels(
          pixels,
          _width,
          _height,
          ui.PixelFormat.rgba8888,
          completer.complete,
        );
        final next = await completer.future;
        _image?.dispose();
        _image = next;
      }
    } else {
      if (_codec == null || (item.kind == 'gif' && time < _gifStart)) {
        _codec?.dispose();
        _codec = await ui.instantiateImageCodec(
          await File(item.path).readAsBytes(),
          targetWidth: _width,
          targetHeight: _height,
        );
        _gifStart = 0;
        _gifEnd = 0;
        _gifIndex = -1;
      }
      if (item.kind == 'image') {
        _image ??= await _sized((await _codec!.getNextFrame()).image);
      } else {
        while (_gifIndex < 0 || time >= _gifEnd) {
          final next = await _codec!.getNextFrame();
          _image?.dispose();
          _image = await _sized(next.image);
          _gifStart = _gifEnd;
          _gifEnd += math.max(10000, next.duration.inMicroseconds);
          _gifIndex++;
        }
      }
    }
    return _image!.clone();
  }

  Future<ui.Image> _sized(ui.Image image) async {
    if (image.width == _width && image.height == _height) return image;
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawImageRect(
      image,
      ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      ui.Rect.fromLTWH(0, 0, _width.toDouble(), _height.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.medium,
    );
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(_width, _height);
    } finally {
      picture.dispose();
      image.dispose();
    }
  }

  Future<Uint8List> _readPixels(int count) async {
    final out = Uint8List(count);
    var at = 0;
    while (at < count) {
      if (_chunkAt == _chunk.length) {
        if (!await _bytes!.moveNext()) {
          await _stopVideo();
          throw const FormatException(
            'Video decoder ended before requested frame',
          );
        }
        _chunk = _bytes!.current;
        _chunkAt = 0;
      }
      final take = math.min(count - at, _chunk.length - _chunkAt);
      out.setRange(at, at + take, _chunk, _chunkAt);
      at += take;
      _chunkAt += take;
    }
    return out;
  }

  Future<void> _stopVideo() async {
    final process = _process;
    _process = null;
    process?.kill();
    await _bytes?.cancel();
    _bytes = null;
    if (process != null) await process.exitCode;
    _chunk = const [];
    _chunkAt = 0;
    _videoIndex = -1;
    _videoAnchor = -1;
  }

  Future<void> _reset() async {
    await _stopVideo();
    _codec?.dispose();
    _codec = null;
    _image?.dispose();
    _image = null;
    _path = null;
    _info = null;
  }

  Future<void> dispose() async {
    _disposed = true;
    await _pending;
    await _reset();
  }
}
