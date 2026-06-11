import 'dart:math' as math;
import 'dart:ui';

import '../../../domain/entities/stroke.dart';

enum DetectedShape { circle, triangle, square }

class ShapeResult {
  final DetectedShape shape;
  final List<StrokePoint> perfectedPoints;

  ShapeResult(this.shape, this.perfectedPoints);
}

class ShapeDetector {
  /// Detects if the given points form a recognizable shape.
  /// Returns a [ShapeResult] with perfected points if detected, else null.
  static ShapeResult? detect(List<StrokePoint> points, double baseWidth) {
    if (points.length < 10) return null;

    // 1. Check for polygons (Triangle, Square) - do this first as it's more specific
    final polyResult = _tryDetectPolygon(points);
    if (polyResult != null) return polyResult;

    // 2. Check for circle
    final circleResult = _tryDetectCircle(points);
    if (circleResult != null) return circleResult;

    return null;
  }

  static ShapeResult? _tryDetectCircle(List<StrokePoint> points) {
    // Calculate centroid
    double sumX = 0, sumY = 0;
    for (final p in points) {
      sumX += p.x;
      sumY += p.y;
    }
    final center = Offset(sumX / points.length, sumY / points.length);

    // Calculate distances to center
    final distances = points.map((p) => (Offset(p.x, p.y) - center).distance).toList();
    final avgDist = distances.reduce((a, b) => a + b) / distances.length;

    if (avgDist < 5) return null; // Too small

    // Check variance of distances
    double varianceSum = 0;
    for (final d in distances) {
      varianceSum += math.pow(d - avgDist, 2);
    }
    final stdDev = math.sqrt(varianceSum / distances.length);
    final relativeError = stdDev / avgDist;

    // Check if it's closed-ish
    final start = Offset(points.first.x, points.first.y);
    final end = Offset(points.last.x, points.last.y);
    final isClosed = (start - end).distance < avgDist * 1.0;

    // Circles have low relative error (usually < 0.1). Squares have ~0.11-0.15.
    if (relativeError < 0.11 && isClosed) {
      // It's a circle! Generate perfected points.
      final perfected = <StrokePoint>[];
      const segments = 72; // Smooth circle
      final startTimestamp = points.first.timestampMs;
      final endTimestamp = points.last.timestampMs;
      final duration = endTimestamp - startTimestamp;

      for (var i = 0; i <= segments; i++) {
        final angle = (i / segments) * 2 * math.pi;
        perfected.add(StrokePoint(
          x: center.dx + math.cos(angle) * avgDist,
          y: center.dy + math.sin(angle) * avgDist,
          pressure: 0.8,
          timestampMs: startTimestamp + (duration * i ~/ segments),
        ));
      }
      return ShapeResult(DetectedShape.circle, perfected);
    }

    return null;
  }

  static ShapeResult? _tryDetectPolygon(List<StrokePoint> points) {
    final simplified = _rdp(points, 10.0);
    
    // Close the polygon if it's nearly closed
    final start = Offset(simplified.first.x, simplified.first.y);
    final end = Offset(simplified.last.x, simplified.last.y);
    final avgSide = _avgSideLength(simplified);
    
    List<StrokePoint> poly = simplified;
    if ((start - end).distance < avgSide * 0.8) {
      poly = [...simplified.take(simplified.length - 1), simplified.first];
    }

    // Vertices = points in the simplified path (minus the closing point if any)
    final vertexCount = poly.length - 1;

    if (vertexCount == 3) {
      return ShapeResult(DetectedShape.triangle, _generatePolyPoints(poly));
    } else if (vertexCount == 4) {
      return ShapeResult(DetectedShape.square, _generatePolyPoints(poly));
    }

    return null;
  }

  static double _avgSideLength(List<StrokePoint> points) {
    if (points.length < 2) return 0;
    double dist = 0;
    for (int i = 0; i < points.length - 1; i++) {
      dist += (Offset(points[i].x, points[i].y) - Offset(points[i+1].x, points[i+1].y)).distance;
    }
    return dist / (points.length - 1);
  }

  static List<StrokePoint> _generatePolyPoints(List<StrokePoint> vertices) {
    final perfected = <StrokePoint>[];
    final startTimestamp = vertices.first.timestampMs;
    final endTimestamp = vertices.last.timestampMs;
    final totalDuration = endTimestamp - startTimestamp;

    // Calculate total path length
    double totalDist = 0;
    final segmentDistances = <double>[];
    for (int i = 0; i < vertices.length - 1; i++) {
      final d = (Offset(vertices[i].x, vertices[i].y) - Offset(vertices[i+1].x, vertices[i+1].y)).distance;
      segmentDistances.add(d);
      totalDist += d;
    }

    double currentDist = 0;
    for (int i = 0; i < vertices.length - 1; i++) {
      final p1 = vertices[i];
      final p2 = vertices[i+1];
      final segDist = segmentDistances[i];
      
      final segPoints = (segDist / 5).clamp(2, 50).toInt();
      for (int j = 0; j < segPoints; j++) {
        final t = j / segPoints;
        final timeT = totalDist == 0 ? 0.0 : (currentDist + t * segDist) / totalDist;
        perfected.add(StrokePoint(
          x: p1.x + (p2.x - p1.x) * t,
          y: p1.y + (p2.y - p1.y) * t,
          pressure: 0.8,
          timestampMs: startTimestamp + (totalDuration * timeT).toInt(),
        ));
      }
      currentDist += segDist;
    }
    perfected.add(vertices.last);

    return perfected;
  }

  /// Ramer-Douglas-Peucker simplification
  static List<StrokePoint> _rdp(List<StrokePoint> points, double epsilon) {
    if (points.length < 3) return points;

    int index = -1;
    double maxDist = 0;

    for (int i = 1; i < points.length - 1; i++) {
      double dist = _perpendicularDistance(points[i], points.first, points.last);
      if (dist > maxDist) {
        index = i;
        maxDist = dist;
      }
    }

    if (maxDist > epsilon) {
      final left = _rdp(points.sublist(0, index + 1), epsilon);
      final right = _rdp(points.sublist(index), epsilon);
      return [...left.take(left.length - 1), ...right];
    } else {
      return [points.first, points.last];
    }
  }

  static double _perpendicularDistance(StrokePoint p, StrokePoint a, StrokePoint b) {
    final x = p.x, y = p.y;
    final x1 = a.x, y1 = a.y;
    final x2 = b.x, y2 = b.y;

    final numerator = ((y2 - y1) * x - (x2 - x1) * y + x2 * y1 - y2 * x1).abs();
    final denominator = math.sqrt(math.pow(y2 - y1, 2) + math.pow(x2 - x1, 2));
    if (denominator == 0) return (Offset(x, y) - Offset(x1, y1)).distance;
    return numerator / denominator;
  }
}
