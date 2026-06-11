import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show Listenable;
import 'package:flutter/rendering.dart';

import '../../../app/theme/tokens.dart';
import '../../../domain/entities/image_object.dart';
import '../../../domain/entities/page_spec.dart';
import '../../../domain/entities/stroke.dart';
import '../engine/active_stroke_controller.dart';
import '../engine/image_raster_cache.dart';
import '../engine/page_camera.dart';
import '../engine/page_transform.dart';
import '../engine/pdf_background_cache.dart';
import '../engine/ribbon_builder.dart';

/// Per-stroke committed geometry cache, keyed by stroke id. Ops can keep
/// an id while changing geometry (lasso move/scale via [transformStroke],
/// and their undos), so each entry remembers the inputs the ribbon was
/// built from and rebuilds when they change. Recolors reuse the points
/// list, so they stay cache hits (color is applied at draw time, not
/// baked into the path).
class StrokePathCache {
  final _entries =
      <String, ({List<StrokePoint> points, double baseWidth, Path path})>{};

  Path of(Stroke stroke) {
    final entry = _entries[stroke.id];
    if (entry != null &&
        identical(entry.points, stroke.points) &&
        entry.baseWidth == stroke.baseWidth) {
      return entry.path;
    }
    final path = RibbonBuilder.build(stroke);
    _entries[stroke.id] =
        (points: stroke.points, baseWidth: stroke.baseWidth, path: path);
    return path;
  }

  void retainOnly(Iterable<Stroke> strokes) {
    final live = {for (final s in strokes) s.id};
    _entries.removeWhere((id, _) => !live.contains(id));
  }
}

void _applyCamera(Canvas canvas, CameraView camera) {
  canvas
    ..translate(camera.offset.dx, camera.offset.dy)
    ..scale(camera.scale);
}

/// Page background: shadow, paper, template pattern, PDF raster.
class PaperPainter extends CustomPainter {
  PaperPainter({
    required this.camera,
    required this.spec,
    required this.isWhiteboard,
    this.pdfCache,
  }) : super(
          repaint: pdfCache == null
              ? camera
              : Listenable.merge([camera, pdfCache]),
        );

  final CameraView camera;
  final PageSpec spec;
  final bool isWhiteboard;
  final PdfBackgroundCache? pdfCache;

  @override
  void paint(Canvas canvas, Size size) {
    if (isWhiteboard) {
      // The whiteboard surface is the screen itself â€” endless paper with
      // a dot grid anchored to content space, so it pans and zooms with
      // the ink.
      canvas.drawRect(Offset.zero & size, Paint()..color = InkColors.page);
      _paintWhiteboardDots(canvas, size);
      return;
    }
    _applyCamera(canvas, camera);
    final transform = PageTransform(spec);
    final displayRect = Offset.zero & transform.displaySize;

    canvas.drawShadow(
      Path()..addRect(displayRect.shift(const Offset(0, 1))),
      const Color(0x40253237),
      6 / camera.scale,
      false,
    );
    canvas.drawRect(displayRect, Paint()..color = InkColors.page);

    canvas.save();
    canvas.clipRect(displayRect);
    transform.applyTo(canvas);

    final pdfIndex = spec.pdfPageIndex;
    if (pdfIndex != null && pdfCache != null) {
      final image = pdfCache!.pageImage(pdfIndex, camera.scale);
      if (image != null) {
        canvas.drawImageRect(
          image,
          Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
          Rect.fromLTWH(0, 0, spec.width, spec.height),
          Paint()..filterQuality = FilterQuality.medium,
        );
      }
    } else {
      _paintTemplate(canvas);
    }
    canvas.restore();
  }

  /// Dot grid in content coordinates, density-adapted to zoom: the
  /// stride doubles until dots sit â‰¥14 screen px apart, so zooming out
  /// coarsens the grid instead of flooding the screen.
  void _paintWhiteboardDots(Canvas canvas, Size size) {
    var spacing = 32.0;
    while (spacing * camera.scale < 14) {
      spacing *= 2;
    }
    final topLeft = camera.screenToDisplay(Offset.zero);
    final bottomRight = camera.screenToDisplay(Offset(size.width, size.height));

    final left = (topLeft.dx / spacing).floor() * spacing;
    final top = (topLeft.dy / spacing).floor() * spacing;
    final right = bottomRight.dx;
    final bottom = bottomRight.dy;

    _applyCamera(canvas, camera);
    // Keep dots legible at any zoom: ~1.2 content px, never under ~0.9
    // screen px.
    final radius = (1.2).clamp(0.9 / camera.scale, 3.0 / camera.scale);
    final dot = Paint()..color = const Color(0xFFCBD5D8);
    for (var y = top; y <= bottom; y += spacing) {
      for (var x = left; x <= right; x += spacing) {
        canvas.drawCircle(Offset(x, y), radius, dot);
      }
    }
  }

  void _paintTemplate(Canvas canvas) {
    const spacing = 32.0;
    const margin = 48.0;
    final paint = Paint()
      ..color = const Color(0xFFDDE5E7) // quiet rule lines on white
      ..strokeWidth = 1 / camera.scale.clamp(1, 8);
    switch (spec.template) {
      case PaperTemplate.blank:
        break;
      case PaperTemplate.lined:
        for (var y = margin + spacing; y < spec.height - margin / 2; y += spacing) {
          canvas.drawLine(Offset(margin / 2, y), Offset(spec.width - margin / 2, y), paint);
        }
      case PaperTemplate.grid:
        for (var y = spacing; y < spec.height; y += spacing) {
          canvas.drawLine(Offset(0, y), Offset(spec.width, y), paint);
        }
        for (var x = spacing; x < spec.width; x += spacing) {
          canvas.drawLine(Offset(x, 0), Offset(x, spec.height), paint);
        }
      case PaperTemplate.dotted:
        final dot = Paint()..color = const Color(0xFFCBD5D8);
        for (var y = spacing; y < spec.height; y += spacing) {
          for (var x = spacing; x < spec.width; x += spacing) {
            canvas.drawCircle(Offset(x, y), 1.2, dot);
          }
        }
    }
  }

  @override
  bool shouldRepaint(PaperPainter oldDelegate) =>
      oldDelegate.spec != spec ||
      oldDelegate.camera.scale != camera.scale ||
      oldDelegate.camera.offset != camera.offset;
}

/// Imported images â€” always under the ink.
class ImagesPainter extends CustomPainter {
  ImagesPainter({
    required this.camera,
    required this.spec,
    required this.images,
    required this.cache,
    this.overrideRects = const {},
  }) : super(repaint: Listenable.merge([camera, cache]));

  final CameraView camera;
  final PageSpec spec;
  final List<ImageObject> images;
  final ImageRasterCache cache;

  /// Live-drag preview: image id â†’ its current rect.
  final Map<String, Rect> overrideRects;

  @override
  void paint(Canvas canvas, Size size) {
    if (images.isEmpty) return;
    _applyCamera(canvas, camera);
    final transform = PageTransform(spec);
    canvas.clipRect(Offset.zero & transform.displaySize);
    transform.applyTo(canvas);

    for (final obj in images) {
      final rect = overrideRects[obj.id] ?? obj.rect;
      final image = cache.imageFor(obj.assetPath);
      if (image == null) {
        // Placeholder while decoding.
        canvas.drawRect(rect, Paint()..color = const Color(0x14253237));
        continue;
      }
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        rect,
        Paint()..filterQuality = FilterQuality.medium,
      );
    }
  }

  @override
  bool shouldRepaint(ImagesPainter oldDelegate) =>
      oldDelegate.images != images ||
      oldDelegate.overrideRects != overrideRects ||
      oldDelegate.spec != spec ||
      oldDelegate.camera.scale != camera.scale ||
      oldDelegate.camera.offset != camera.offset;
}

/// All committed strokes. [hiddenIds] hides strokes being live-dragged
/// (the overlay draws their preview instead).
class CommittedInkPainter extends CustomPainter {
  CommittedInkPainter({
    required this.camera,
    required this.spec,
    required this.strokes,
    required this.revision,
    required this.cache,
    this.hiddenIds = const {},
    this.clipToPage = true,
  }) : super(repaint: camera);

  final CameraView camera;
  final PageSpec spec;
  final List<Stroke> strokes;
  final int revision;
  final StrokePathCache cache;
  final Set<String> hiddenIds;
  final bool clipToPage;

  @override
  void paint(Canvas canvas, Size size) {
    _applyCamera(canvas, camera);
    final transform = PageTransform(spec);
    if (clipToPage) canvas.clipRect(Offset.zero & transform.displaySize);
    transform.applyTo(canvas);
    final paint = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.fill;
    for (final stroke in strokes) {
      if (hiddenIds.contains(stroke.id)) continue;
      paint.color = stroke.color;
      canvas.drawPath(cache.of(stroke), paint);
    }
  }

  @override
  bool shouldRepaint(CommittedInkPainter oldDelegate) =>
      oldDelegate.revision != revision ||
      oldDelegate.strokes != strokes ||
      oldDelegate.hiddenIds != hiddenIds ||
      oldDelegate.spec != spec ||
      oldDelegate.camera.scale != camera.scale ||
      oldDelegate.camera.offset != camera.offset;
}

/// Only the in-progress pen stroke â€” the 120Hz hot path.
class ActiveStrokePainter extends CustomPainter {
  ActiveStrokePainter({
    required this.camera,
    required this.spec,
    required this.controller,
    this.clipToPage = true,
  }) : super(repaint: Listenable.merge([camera, controller]));

  final CameraView camera;
  final PageSpec spec;
  final ActiveStrokeController controller;
  final bool clipToPage;

  @override
  void paint(Canvas canvas, Size size) {
    if (!controller.isActive) return;
    _applyCamera(canvas, camera);
    final transform = PageTransform(spec);
    if (clipToPage) canvas.clipRect(Offset.zero & transform.displaySize);
    transform.applyTo(canvas);
    final paint = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.fill
      ..color = controller.color;
    canvas.drawPath(controller.path, paint);

    final tail = controller.predictedTail;
    if (tail != null) {
      canvas.drawPath(
        tail,
        Paint()
          ..isAntiAlias = true
          ..style = PaintingStyle.stroke
          ..strokeWidth = controller.predictedTailWidth
          ..strokeCap = StrokeCap.round
          ..color = controller.color,
      );
    }
  }

  @override
  bool shouldRepaint(ActiveStrokePainter oldDelegate) => true;
}

/// Renders one page (paper + images + ink) into a picture â€” shared by
/// the thumbnail generator so thumbnails use production geometry.
ui.Picture renderPageToPicture({
  required PageSpec spec,
  required List<Stroke> strokes,
  required StrokePathCache cache,
}) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
      Rect.fromLTWH(0, 0, spec.width, spec.height), Paint()..color = InkColors.page);
  final paint = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.fill;
  for (final stroke in strokes) {
    paint.color = stroke.color;
    canvas.drawPath(cache.of(stroke), paint);
  }
  return recorder.endRecording();
}
