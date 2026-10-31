import 'dart:ui' as ui;
import 'dart:math' as math;

import 'model.dart';

// Preview and generated output use the same Canvas coordinate system.
void paintStill(
  ui.Canvas canvas,
  ui.Size size,
  ui.Image image,
  Still still, {
  bool transparent = false,
}) {
  canvas.save();
  canvas.clipRect(ui.Offset.zero & size);
  if (!transparent) {
    canvas.drawColor(const ui.Color(0xff000000), ui.BlendMode.src);
  }
  final ratios = [size.width / image.width, size.height / image.height];
  final factor =
      (still.cover ? ratios.reduce(math.max) : ratios.reduce(math.min)) *
      still.scale;
  final w = image.width * factor, h = image.height * factor;
  final rect = ui.Rect.fromLTWH(
    (size.width - w) / 2 + still.x * size.width,
    (size.height - h) / 2 + still.y * size.height,
    w,
    h,
  );
  canvas.drawImageRect(
    image,
    ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    rect,
    ui.Paint()..filterQuality = ui.FilterQuality.high,
  );
  canvas.restore();
}

void _paintLegacyFrame(
  ui.Canvas canvas,
  ui.Size size,
  ui.Image image,
  Still item, {
  int localUs = 0,
  int sourceUs = 0,
  List<Caption> captions = const [],
  double referenceWidth = 1920,
  bool transparentBackground = false,
}) {
  final bounds = ui.Offset.zero & size;
  canvas.save();
  canvas.clipRect(bounds);
  if (!transparentBackground) {
    canvas.drawColor(const ui.Color(0xff000000), ui.BlendMode.src);
  }
  final weight = (1 - localUs / math.max(1, item.effectDurationUs)).clamp(
    0.0,
    1.0,
  );
  double amount(String name) => (item.effects[name] ?? 0) * weight;
  final frame = math.max(0, (localUs * fps + 500000) ~/ 1000000);
  final shake = amount('shake'), zoom = 1 + amount('zoom') * .35 + shake * .06;
  canvas.save();
  canvas.translate(
    size.width / 2 + math.sin(frame * 2.17) * shake * size.width * .035,
    size.height / 2 + math.cos(frame * 1.83) * shake * size.height * .035,
  );
  canvas.rotate(math.sin(frame * 1.31) * shake * .025);
  canvas.scale(zoom);
  canvas.translate(-size.width / 2, -size.height / 2);
  final blur = amount('blur');
  if (blur > 0) {
    canvas.saveLayer(
      bounds,
      ui.Paint()
        ..imageFilter = ui.ImageFilter.blur(
          sigmaX: blur * 18 * size.width / referenceWidth,
          sigmaY: blur * 18 * size.width / referenceWidth,
        ),
    );
  }
  paintStill(canvas, size, image, item, transparent: transparentBackground);
  if (blur > 0) canvas.restore();
  final glow = amount('glow');
  if (glow > 0) {
    canvas.saveLayer(
      bounds,
      ui.Paint()
        ..blendMode = ui.BlendMode.screen
        ..color = ui.Color.fromRGBO(255, 255, 255, glow * .7)
        ..imageFilter = ui.ImageFilter.blur(
          sigmaX: 12 * size.width / referenceWidth,
          sigmaY: 12 * size.width / referenceWidth,
        ),
    );
    paintStill(canvas, size, image, item, transparent: transparentBackground);
    canvas.restore();
  }
  final rgb = amount('rgb');
  if (rgb > 0) {
    for (final red in [true, false]) {
      canvas.saveLayer(
        bounds,
        ui.Paint()
          ..blendMode = ui.BlendMode.screen
          ..colorFilter = ui.ColorFilter.matrix([
            red ? rgb : 0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            red ? 0 : rgb,
            0,
            0,
            0,
            0,
            0,
            1,
            0,
          ]),
      );
      canvas.translate((red ? -1 : 1) * rgb * size.width * .025, 0);
      paintStill(canvas, size, image, item, transparent: transparentBackground);
      canvas.restore();
    }
  }
  final glitch = amount('glitch');
  if (glitch > 0 && frame % 5 < 3) {
    for (var band = 0; band < 4; band++) {
      canvas.save();
      final y = ((frame * 17 + band * 131) % 997) / 997 * size.height;
      canvas.clipRect(ui.Rect.fromLTWH(0, y, size.width, size.height * .045));
      canvas.translate(
        math.sin(frame + band * 2) * glitch * size.width * .12,
        0,
      );
      paintStill(canvas, size, image, item, transparent: transparentBackground);
      canvas.restore();
    }
  }
  canvas.restore();
  final flash = amount('flash');
  if (flash > 0) {
    canvas.drawRect(
      bounds,
      ui.Paint()
        ..color = ui.Color.fromRGBO(
          255,
          255,
          255,
          flash * weight * weight * .9,
        ),
    );
  }
  _paintCaptions(canvas, size, captions, sourceUs, referenceWidth);
  canvas.restore();
}

class VisualFrame {
  final Still media;
  final ui.Image image;
  final int localUs;
  final double opacity;
  const VisualFrame(this.media, this.image, this.localUs, this.opacity);
}

// All temporal evaluation uses the same composition frame in preview and export.
void paintFrame(
  ui.Canvas canvas,
  ui.Size size,
  ui.Image image,
  Still item, {
  int localUs = 0,
  int sourceUs = 0,
  List<Caption> captions = const [],
  double referenceWidth = 1920,
  Project? project,
  ui.Image? previousImage,
  Still? previousItem,
  List<VisualFrame> overlays = const [],
  bool transparentBackground = false,
}) {
  final rate = project?.frameRate ?? fps;
  localUs = math.max(0, (localUs * rate + 500000) ~/ 1000000) * 1000000 ~/ rate;
  sourceUs = project == null
      ? sourceUs
      : project.startUs +
            math.max(
                  0,
                  ((sourceUs - project.startUs) * rate + 500000) ~/ 1000000,
                ) *
                1000000 ~/
                rate;
  final bounds = ui.Offset.zero & size;
  void base(ui.Canvas canvas) => _paintLegacyFrame(
    canvas,
    size,
    image,
    item,
    localUs: localUs,
    sourceUs: sourceUs,
    captions: const [],
    referenceWidth: referenceWidth,
    transparentBackground: transparentBackground,
  );
  void Function(ui.Canvas) draw = base;
  // Animation values are absolute offsets/scale/radians/opacity, in track order.
  final animated = draw;
  draw = (canvas) {
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    var opacity = 1.0;
    for (final track in item.animations.where((t) => t.enabled)) {
      final v = track.evaluate(localUs);
      switch (track.property) {
        case AnimationProperty.x:
          canvas.translate(v * size.width, 0);
        case AnimationProperty.y:
          canvas.translate(0, v * size.height);
        case AnimationProperty.scale:
          canvas.scale(v.clamp(.01, 100.0));
        case AnimationProperty.rotation:
          canvas.rotate(v);
        case AnimationProperty.opacity:
          opacity *= v.clamp(0.0, 1.0);
      }
    }
    canvas.translate(-size.width / 2, -size.height / 2);
    canvas.saveLayer(
      bounds,
      ui.Paint()..color = ui.Color.fromRGBO(255, 255, 255, opacity),
    );
    animated(canvas);
    canvas.restore();
    canvas.restore();
  };
  for (final effect in item.effectStack) {
    final next = draw;
    draw = (canvas) => _paintEffect(
      canvas,
      size,
      effect,
      localUs,
      next,
      previousImage: previousImage,
      previousItem: previousItem ?? item,
      referenceWidth: referenceWidth,
    );
  }
  final visuals = draw;
  draw = (canvas) {
    visuals(canvas);
    for (final overlay in overlays) {
      canvas.saveLayer(
        bounds,
        ui.Paint()..color = ui.Color.fromRGBO(255, 255, 255, overlay.opacity),
      );
      paintFrame(
        canvas,
        size,
        overlay.image,
        overlay.media,
        localUs: overlay.localUs,
        sourceUs: sourceUs,
        referenceWidth: referenceWidth,
        transparentBackground: true,
      );
      canvas.restore();
    }
    // Caption-only pass shares the legacy caption layout without repainting media.
    _paintCaptions(canvas, size, captions, sourceUs, referenceWidth);
  };
  if (project != null && project.globalEffectsEnabled) {
    for (final layer in project.globalEffects) {
      final time = layer.localTime(
        sourceUs,
        projectStartUs: project.startUs,
        markers: project.markers.map((m) => MapEntry(m.id, m.timeUs)),
        imageChanges: project.segments.map(
          (s) => project.startUs + (s.startFrame * 1000000 + rate - 1) ~/ rate,
        ),
      );
      if (time == null) continue;
      for (final effect in layer.effects) {
        final next = draw;
        draw = (canvas) => _paintEffect(
          canvas,
          size,
          effect,
          time,
          next,
          holdLast:
              layer.mode == GlobalEffectMode.always ||
              layer.mode == GlobalEffectMode.range,
          previousImage: previousImage,
          previousItem: previousItem ?? item,
          referenceWidth: referenceWidth,
        );
      }
    }
  }
  canvas.save();
  canvas.clipRect(bounds);
  if (!transparentBackground) {
    canvas.drawColor(const ui.Color(0xff000000), ui.BlendMode.src);
  }
  draw(canvas);
  canvas.restore();
}

void _paintEffect(
  ui.Canvas c,
  ui.Size size,
  EffectInstance e,
  int time,
  void Function(ui.Canvas) draw, {
  ui.Image? previousImage,
  Still? previousItem,
  double referenceWidth = 1920,
  bool holdLast = false,
}) {
  final a = e.amountAt(time, holdLast: holdLast).clamp(0.0, 1.0),
      b = ui.Offset.zero & size;
  if (a <= 0) {
    draw(c);
    return;
  }
  final recorder = ui.PictureRecorder();
  draw(ui.Canvas(recorder));
  final incoming = recorder.endRecording();
  void render() => c.drawPicture(incoming);
  final phase =
      time / 1000000 * 2 * math.pi * (e.frequency == 0 ? 6 : e.frequency);
  void shifted(double x, double y) {
    c.save();
    c.translate(x, y);
    render();
    c.restore();
  }

  try {
    switch (e.type) {
      case 'shake':
        c.save();
        c.translate(
          math.sin(phase * 1.17) * a * size.width * .035,
          math.cos(phase * 1.83) * a * size.height * .035,
        );
        render();
        c.restore();
      case 'zoom':
      case 'pulse':
      case 'rotation':
        c.save();
        c.translate(size.width / 2, size.height / 2);
        if (e.type == 'rotation') {
          c.rotate(a * .3);
        } else {
          c.scale(
            1 + a * .35 * (e.type == 'pulse' ? .5 + .5 * math.sin(phase) : 1),
          );
        }
        c.translate(-size.width / 2, -size.height / 2);
        render();
        c.restore();
      case 'pan':
        shifted(a * size.width * .2, 0);
      case 'blur':
        c.saveLayer(
          b,
          ui.Paint()
            ..imageFilter = ui.ImageFilter.blur(
              sigmaX: a * 18 * size.width / referenceWidth,
              sigmaY: a * 18 * size.width / referenceWidth,
            ),
        );
        render();
        c.restore();
      case 'glow':
        render();
        c.saveLayer(
          b,
          ui.Paint()
            ..blendMode = ui.BlendMode.screen
            ..color = ui.Color.fromRGBO(255, 255, 255, a * .7)
            ..imageFilter = ui.ImageFilter.blur(
              sigmaX: 12 * size.width / referenceWidth,
              sigmaY: 12 * size.width / referenceWidth,
            ),
        );
        render();
        c.restore();
      case 'flash':
        render();
        c.drawRect(
          b,
          ui.Paint()..color = ui.Color.fromRGBO(255, 255, 255, a * .9),
        );
      case 'rgb':
        render();
        for (final red in [true, false]) {
          c.saveLayer(
            b,
            ui.Paint()
              ..blendMode = ui.BlendMode.screen
              ..colorFilter = ui.ColorFilter.matrix([
                red ? a : 0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                red ? 0 : a,
                0,
                0,
                0,
                0,
                0,
                1,
                0,
              ]),
          );
          shifted((red ? -1 : 1) * a * size.width * .025, 0);
          c.restore();
        }
      case 'glitch':
        render();
        final frame = time * fps ~/ 1000000;
        for (var band = 0; band < 4; band++) {
          c.save();
          final y = ((frame * 17 + band * 131) % 997) / 997 * size.height;
          c.clipRect(ui.Rect.fromLTWH(0, y, size.width, size.height * .045));
          shifted(math.sin(frame + band * 2) * a * size.width * .12, 0);
          c.restore();
        }
      case 'scanlines':
        render();
        for (
          double y = 0;
          y < size.height;
          y += math.max(2, size.height / 100)
        ) {
          c.drawRect(
            ui.Rect.fromLTWH(0, y, size.width, 1),
            ui.Paint()..color = ui.Color.fromRGBO(0, 0, 0, a * .7),
          );
        }
      case 'vignette':
        render();
        c.drawRect(
          b,
          ui.Paint()
            ..shader = ui.Gradient.radial(
              b.center,
              size.longestSide * .65,
              [const ui.Color(0x00000000), ui.Color.fromRGBO(0, 0, 0, a)],
              [.35, 1],
            ),
        );
      case 'lightSweep':
        render();
        final x = ((time - e.delayUs) / e.durationUs) * size.width;
        c.drawRect(
          b,
          ui.Paint()
            ..blendMode = ui.BlendMode.screen
            ..shader = ui.Gradient.linear(
              ui.Offset(x - size.width * .2, 0),
              ui.Offset(x + size.width * .2, size.height),
              [
                const ui.Color(0x00ffffff),
                ui.Color.fromRGBO(255, 255, 255, a * .8),
                const ui.Color(0x00ffffff),
              ],
              [0, .5, 1],
            ),
        );
      case 'crossfade':
      case 'slide':
      case 'wipe':
        if (previousImage == null) {
          render();
          return;
        }
        paintStill(c, size, previousImage, previousItem!);
        if (e.type == 'crossfade') {
          c.saveLayer(
            b,
            ui.Paint()..color = ui.Color.fromRGBO(255, 255, 255, 1 - a),
          );
          render();
          c.restore();
        }
        if (e.type == 'slide') shifted(a * size.width, 0);
        if (e.type == 'wipe') {
          c.save();
          c.clipRect(ui.Rect.fromLTWH(0, 0, size.width * (1 - a), size.height));
          render();
          c.restore();
        }
      default:
        render();
    }
  } finally {
    incoming.dispose();
  }
}

void _paintCaptions(
  ui.Canvas canvas,
  ui.Size size,
  List<Caption> captions,
  int sourceUs,
  double referenceWidth,
) {
  for (final caption in captions) {
    if (sourceUs < caption.startUs || sourceUs >= caption.endUs) continue;
    final builder =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(
              textAlign: ui.TextAlign.center,
              maxLines: 12,
              fontSize: caption.fontSize * size.width / referenceWidth,
            ),
          )
          ..pushStyle(
            ui.TextStyle(
              color: ui.Color(caption.color),
              fontWeight: ui.FontWeight.w700,
              shadows: [
                const ui.Shadow(
                  color: ui.Color(0xff000000),
                  blurRadius: 4,
                  offset: ui.Offset(1, 2),
                ),
              ],
            ),
          )
          ..addText(caption.text);
    final paragraph = builder.build()
      ..layout(ui.ParagraphConstraints(width: size.width * .9));
    final dx = (caption.x * size.width - paragraph.width / 2).clamp(
      -paragraph.width * .9,
      size.width - paragraph.width * .1,
    );
    final dy = (caption.y * size.height - paragraph.height / 2).clamp(
      0.0,
      math.max(0, size.height - paragraph.height),
    );
    canvas.drawParagraph(paragraph, ui.Offset(dx.toDouble(), dy.toDouble()));
    paragraph.dispose();
  }
}
