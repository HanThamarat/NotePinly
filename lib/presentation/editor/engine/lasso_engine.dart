import 'dart:ui';

import '../../../domain/entities/image_object.dart';
import '../../../domain/entities/stroke.dart';

/// Lasso hit-testing: ray-cast point-in-polygon over sampled stroke
/// points. A stroke is selected when most of it sits inside the loop.
abstract final class LassoEngine {
  static const double _membership = 0.5;

  static bool pointInPolygon(Offset p, List<Offset> polygon) {
    var inside = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final a = polygon[i];
      final b = polygon[j];
      final crosses = (a.dy > p.dy) != (b.dy > p.dy) &&
          p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx;
      if (crosses) inside = !inside;
    }
    return inside;
  }

  static bool strokeInLasso(Stroke stroke, List<Offset> polygon, Rect lassoBounds) {
    if (stroke.points.isEmpty || polygon.length < 3) return false;
    if (!lassoBounds.overlaps(stroke.bounds)) return false;
    var inside = 0;
    // Sample at most ~32 points per stroke; membership is statistical.
    final step = (stroke.points.length / 32).ceil().clamp(1, 1 << 30);
    var sampled = 0;
    for (var i = 0; i < stroke.points.length; i += step) {
      sampled++;
      final p = stroke.points[i];
      if (pointInPolygon(Offset(p.x, p.y), polygon)) inside++;
    }
    return inside / sampled >= _membership;
  }

  static bool imageInLasso(ImageObject image, List<Offset> polygon) {
    if (polygon.length < 3) return false;
    return pointInPolygon(image.rect.center, polygon);
  }

  /// Selection result over one page.
  static ({Set<String> strokeIds, String? imageId}) select({
    required List<Offset> polygon,
    required List<Stroke> strokes,
    required List<ImageObject> images,
  }) {
    Rect bounds = Rect.zero;
    if (polygon.isNotEmpty) {
      var minX = polygon.first.dx, maxX = polygon.first.dx;
      var minY = polygon.first.dy, maxY = polygon.first.dy;
      for (final p in polygon) {
        if (p.dx < minX) minX = p.dx;
        if (p.dx > maxX) maxX = p.dx;
        if (p.dy < minY) minY = p.dy;
        if (p.dy > maxY) maxY = p.dy;
      }
      bounds = Rect.fromLTRB(minX, minY, maxX, maxY);
    }
    final ids = <String>{
      for (final s in strokes)
        if (strokeInLasso(s, polygon, bounds)) s.id,
    };
    String? imageId;
    if (ids.isEmpty) {
      for (final img in images.reversed) {
        if (imageInLasso(img, polygon)) {
          imageId = img.id;
          break;
        }
      }
    }
    return (strokeIds: ids, imageId: imageId);
  }

  /// Bounding box of the selected strokes, inflated for the handles.
  static Rect? selectionBounds(Iterable<Stroke> strokes) {
    Rect? rect;
    for (final s in strokes) {
      rect = rect == null ? s.bounds : rect.expandToInclude(s.bounds);
    }
    return rect;
  }
}
