import 'dart:ui' as ui;
import 'dart:math' as math;

import 'model.dart';

// Preview and generated output use the same Canvas coordinate system.
void paintStill(ui.Canvas canvas, ui.Size size, ui.Image image, Still still) {
  canvas.save();
  canvas.clipRect(ui.Offset.zero & size);
  canvas.drawColor(const ui.Color(0xff000000), ui.BlendMode.src);
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

void paintFrame(
  ui.Canvas canvas,
  ui.Size size,
  ui.Image image,
  Still item, {
  int localUs = 0,
  int sourceUs = 0,
  List<Caption> captions = const [],
  double referenceWidth = 1920,
}) {
  final bounds = ui.Offset.zero & size;
  canvas.save();
  canvas.clipRect(bounds);
  canvas.drawColor(const ui.Color(0xff000000), ui.BlendMode.src);
  final weight = (1 - localUs / math.max(1, item.effectDurationUs)).clamp(
    0.0,
    1.0,
  );
  double amount(String name) => (item.effects[name] ?? 0) * weight;
  final frame = math.max(0, localUs * fps ~/ 1000000);
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
  paintStill(canvas, size, image, item);
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
    paintStill(canvas, size, image, item);
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
      paintStill(canvas, size, image, item);
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
      paintStill(canvas, size, image, item);
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
  canvas.restore();
}
