import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:notepinly/domain/entities/stroke.dart';

Stroke _sampleStroke({String id = 's1'}) => Stroke(
      id: id,
      color: const Color(0xFF005D89),
      baseWidth: 3.5,
      points: const [
        StrokePoint(x: 10, y: 20, pressure: 0.4, timestampMs: 0),
        StrokePoint(x: 14, y: 26, pressure: 0.6, tilt: 0.3, timestampMs: 8),
        StrokePoint(x: 22, y: 31, pressure: 0.9, timestampMs: 16),
      ],
    );

void main() {
  group('Stroke serialization', () {
    test('survives a JSON round-trip exactly', () {
      final original = _sampleStroke();
      final decoded = Stroke.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );

      expect(decoded, equals(original));
      expect(decoded.bounds, equals(original.bounds));
    });

    test('round-trips a point without tilt as null tilt', () {
      final decoded = Stroke.fromJson(_sampleStroke().toJson());
      expect(decoded.points.first.tilt, isNull);
      expect(decoded.points[1].tilt, closeTo(0.3, 1e-9));
    });

    test('encodes color as ARGB int', () {
      final json = _sampleStroke().toJson();
      expect(json['color'], 0xFF005D89);
    });
  });

  group('Stroke bounds', () {
    test('cover all points inflated by half the base width', () {
      final stroke = _sampleStroke();
      expect(stroke.bounds.left, 10 - 1.75);
      expect(stroke.bounds.top, 20 - 1.75);
      expect(stroke.bounds.right, 22 + 1.75);
      expect(stroke.bounds.bottom, 31 + 1.75);
    });

    test('empty stroke has zero bounds', () {
      final stroke = Stroke(
        id: 'empty',
        color: const Color(0xFF000000),
        baseWidth: 2,
        points: const [],
      );
      expect(stroke.bounds, Rect.zero);
    });
  });

  group('Stroke copyWith', () {
    test('recolor preserves identity and geometry', () {
      final stroke = _sampleStroke();
      final recolored = stroke.copyWith(color: const Color(0xFFB02A2D));
      expect(recolored.id, stroke.id);
      expect(recolored.points, stroke.points);
      expect(recolored.color, const Color(0xFFB02A2D));
      expect(recolored.bounds, stroke.bounds);
    });
  });
}
