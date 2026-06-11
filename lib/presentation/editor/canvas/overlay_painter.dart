import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../../../app/theme/tokens.dart';
import '../../../domain/entities/page_spec.dart';
import '../../../domain/entities/stroke.dart';
import '../engine/page_camera.dart';
import '../engine/page_transform.dart';
import 'ink_painters.dart';

/// Live interaction state for the overlay layer: lasso path, selection
/// visuals, drag previews, eraser cursor. Owned by the canvas; painters
/// listen, blocs never see it.
class CanvasInteraction extends ChangeNotifier {
  List<Offset> lassoPoints = []; // page coords
  Rect? selectionBounds; // page coords
  Rect? imageBounds; // page coords (selected image)
  Offset dragOffset = Offset.zero;
  double dragScale = 1;
  Offset dragPivot = Offset.zero;
  List<Stroke> draggedStrokes = const [];
  Offset? eraserCursor; // display coords
  double eraserRadius = 12;
  bool eraserVisible = false;

  void update(void Function() change) {
    change();
    notifyListeners();
  }

  void clearTransient() {
    lassoPoints = [];
    draggedStrokes = const [];
    dragOffset = Offset.zero;
    dragScale = 1;
    eraserVisible = false;
    notifyListeners();
  }
}

const double selectionHandleRadius = 7;

/// Corner handle positions for a selection/image rect, in page coords.
List<Offset> handlePositions(Rect rect) =>
    [rect.topLeft, rect.topRight, rect.bottomRight, rect.bottomLeft];

class OverlayPainter extends CustomPainter {
  OverlayPainter({
    required this.camera,
    required this.spec,
    required this.interaction,
    required this.pathCache,
  }) : super(repaint: Listenable.merge([camera, interaction]));

  final CameraView camera;
  final PageSpec spec;
  final CanvasInteraction interaction;
  final StrokePathCache pathCache;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..translate(camera.offset.dx, camera.offset.dy)
      ..scale(camera.scale);
    final transform = PageTransform(spec);
    transform.applyTo(canvas);
    final onePx = 1 / camera.scale;

    _paintDraggedStrokes(canvas);
    _paintLasso(canvas, onePx);
    _paintSelection(canvas, onePx, interaction.selectionBounds);
    _paintSelection(canvas, onePx, interaction.imageBounds);
    _paintEraser(canvas, transform, onePx);
  }

  void _paintDraggedStrokes(Canvas canvas) {
    if (interaction.draggedStrokes.isEmpty) return;
    canvas.save();
    canvas.translate(
      interaction.dragPivot.dx + interaction.dragOffset.dx,
      interaction.dragPivot.dy + interaction.dragOffset.dy,
    );
    canvas.scale(interaction.dragScale);
    canvas.translate(-interaction.dragPivot.dx, -interaction.dragPivot.dy);
    final paint = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.fill;
    for (final stroke in interaction.draggedStrokes) {
      paint.color = stroke.color;
      canvas.drawPath(pathCache.of(stroke), paint);
    }
    canvas.restore();
  }

  void _paintLasso(Canvas canvas, double onePx) {
    final pts = interaction.lassoPoints;
    if (pts.length < 2) return;
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    _drawDashedPath(
      canvas,
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 * onePx
        ..color = InkColors.primary,
      dash: 6 * onePx,
    );
  }

  void _paintSelection(Canvas canvas, double onePx, Rect? bounds) {
    if (bounds == null) return;
    var rect = bounds;
    if (interaction.draggedStrokes.isNotEmpty ||
        interaction.dragOffset != Offset.zero ||
        interaction.dragScale != 1) {
      // Follow the live drag.
      final p = interaction.dragPivot;
      rect = Rect.fromPoints(
        (bounds.topLeft - p) * interaction.dragScale + p + interaction.dragOffset,
        (bounds.bottomRight - p) * interaction.dragScale + p + interaction.dragOffset,
      );
    }
    final outer = rect.inflate(6 * onePx);
    _drawDashedPath(
      canvas,
      Path()..addRect(outer),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 * onePx
        ..color = InkColors.primary,
      dash: 5 * onePx,
    );
    final fill = Paint()..color = InkColors.page;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 * onePx
      ..color = InkColors.primary;
    for (final corner in handlePositions(outer)) {
      canvas.drawCircle(corner, selectionHandleRadius * onePx, fill);
      canvas.drawCircle(corner, selectionHandleRadius * onePx, ring);
    }
  }

  void _paintEraser(Canvas canvas, PageTransform transform, double onePx) {
    final cursor = interaction.eraserCursor;
    if (!interaction.eraserVisible || cursor == null) return;
    final pagePoint = transform.displayToPage(cursor);
    canvas.drawCircle(
      pagePoint,
      interaction.eraserRadius,
      Paint()..color = const Color(0x14177F8E),
    );
    canvas.drawCircle(
      pagePoint,
      interaction.eraserRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 * onePx
        ..color = InkColors.primary,
    );
  }

  void _drawDashedPath(Canvas canvas, Path path, Paint paint,
      {required double dash}) {
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + dash;
      }
    }
  }

  @override
  bool shouldRepaint(OverlayPainter oldDelegate) => true;
}
