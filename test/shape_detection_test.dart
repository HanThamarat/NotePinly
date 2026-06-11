import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:notepinly/domain/entities/stroke.dart';
import 'package:notepinly/presentation/editor/engine/shape_detector.dart';

void main() {
  group('ShapeDetector', () {
    test('detects a rough circle', () {
      final points = <StrokePoint>[];
      const radius = 50.0;
      const center = math.Point(100.0, 100.0);
      
      // Generate a slightly noisy circle
      for (var i = 0; i < 40; i++) {
        final angle = (i / 40) * 2 * math.pi;
        final noise = (math.Random(i).nextDouble() - 0.5) * 4.0;
        points.add(StrokePoint(
          x: center.x + math.cos(angle) * (radius + noise),
          y: center.y + math.sin(angle) * (radius + noise),
          pressure: 0.5,
          timestampMs: i * 10,
        ));
      }
      // Close it
      points.add(points.first.copyWith(timestampMs: 400));

      final result = ShapeDetector.detect(points, 2.0);
      expect(result, isNotNull);
      expect(result!.shape, DetectedShape.circle);
      // Perfected circle should have points very close to radius 50
      for (final p in result.perfectedPoints) {
        final dist = math.sqrt(math.pow(p.x - center.x, 2) + math.pow(p.y - center.y, 2));
        expect(dist, closeTo(radius, 5.0));
      }
    });

    test('detects a rough triangle', () {
      final points = <StrokePoint>[
        // Side 1
        for (var i = 0; i < 10; i++) StrokePoint(x: i * 10.0, y: i * 10.0, pressure: 0.5, timestampMs: i * 10),
        // Side 2
        for (var i = 0; i < 10; i++) StrokePoint(x: 100.0 + i * 10.0, y: 100.0 - i * 10.0, pressure: 0.5, timestampMs: 100 + i * 10),
        // Side 3
        for (var i = 0; i < 20; i++) StrokePoint(x: 200.0 - i * 10.0, y: 0.0, pressure: 0.5, timestampMs: 200 + i * 10),
      ];
      points.add(points.first.copyWith(timestampMs: 400));

      final result = ShapeDetector.detect(points, 2.0);
      expect(result, isNotNull);
      expect(result!.shape, DetectedShape.triangle);
    });

    test('detects a rough square', () {
      final points = <StrokePoint>[
        // Top
        for (var i = 0; i < 10; i++) StrokePoint(x: i * 10.0, y: 0.0, pressure: 0.5, timestampMs: i * 10),
        // Right
        for (var i = 0; i < 10; i++) StrokePoint(x: 100.0, y: i * 10.0, pressure: 0.5, timestampMs: 100 + i * 10),
        // Bottom
        for (var i = 0; i < 10; i++) StrokePoint(x: 100.0 - i * 10.0, y: 100.0, pressure: 0.5, timestampMs: 200 + i * 10),
        // Left
        for (var i = 0; i < 10; i++) StrokePoint(x: 0.0, y: 100.0 - i * 10.0, pressure: 0.5, timestampMs: 300 + i * 10),
      ];
      points.add(points.first.copyWith(timestampMs: 400));

      final result = ShapeDetector.detect(points, 2.0);
      expect(result, isNotNull);
      expect(result!.shape, DetectedShape.square);
    });

    test('ignores a random scribble', () {
      final points = <StrokePoint>[
        for (var i = 0; i < 50; i++) 
          StrokePoint(
            x: math.Random(i).nextDouble() * 100, 
            y: math.Random(i + 1).nextDouble() * 100, 
            pressure: 0.5, 
            timestampMs: i * 10
          ),
      ];
      final result = ShapeDetector.detect(points, 2.0);
      expect(result, isNull);
    });
  });
}
