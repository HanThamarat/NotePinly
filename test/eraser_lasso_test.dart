import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:notepinly/domain/entities/document_op.dart';
import 'package:notepinly/domain/entities/image_object.dart';
import 'package:notepinly/domain/entities/stroke.dart';
import 'package:notepinly/presentation/editor/canvas/ink_painters.dart';
import 'package:notepinly/presentation/editor/engine/eraser_engine.dart';
import 'package:notepinly/presentation/editor/engine/lasso_engine.dart';

Stroke _line(String id, double y, {double x0 = 0, double x1 = 100}) {
  final n = 11;
  return Stroke(
    id: id,
    color: const Color(0xFF161C1E),
    baseWidth: 3,
    points: [
      for (var i = 0; i < n; i++)
        StrokePoint(
          x: x0 + (x1 - x0) * i / (n - 1),
          y: y,
          pressure: 0.5,
          timestampMs: i * 8,
        ),
    ],
  );
}

void main() {
  group('EraserEngine.hits', () {
    test('hits when the circle touches the path', () {
      final stroke = _line('a', 50);
      expect(EraserEngine.hits(stroke, const Offset(50, 55), 8), isTrue);
      expect(EraserEngine.hits(stroke, const Offset(50, 80), 8), isFalse);
    });

    test('accounts for the stroke width', () {
      final stroke = _line('a', 50);
      // 8 (radius) + 1.5 (half width) reaches y=50 from y=59.
      expect(EraserEngine.hits(stroke, const Offset(50, 59), 8), isTrue);
    });
  });

  group('EraserEngine.split', () {
    test('splits a line into two fragments around the hole', () {
      final stroke = _line('a', 0);
      var seq = 0;
      final fragments =
          EraserEngine.split(stroke, const Offset(50, 0), 8, () => 'f${seq++}');
      expect(fragments, hasLength(2));
      expect(fragments[0].points.last.x, lessThan(42));
      expect(fragments[1].points.first.x, greaterThan(58));
      expect(fragments[0].color, stroke.color);
    });

    test('erasing the whole stroke leaves nothing', () {
      final stroke = _line('a', 0, x0: 40, x1: 60);
      final fragments =
          EraserEngine.split(stroke, const Offset(50, 0), 30, () => 'f');
      expect(fragments, isEmpty);
    });
  });

  group('EraserSession', () {
    test('stroke mode removes whole strokes; one op per drag', () {
      final session = EraserSession(
        mode: EraserMode.stroke,
        radius: 8,
        strokes: [_line('a', 0), _line('b', 100)],
        nextId: () => 'x',
      );
      expect(session.eraseAt(const Offset(50, 0)), isTrue);
      expect(session.eraseAt(const Offset(50, 50)), isFalse);
      final result = session.commit();
      expect(result.removed.map((s) => s.id), ['a']);
      expect(result.added, isEmpty);
      expect(session.visibleStrokes.map((s) => s.id), ['b']);
    });

    test('area mode splits and re-splitting fragments stays consistent', () {
      var seq = 0;
      final session = EraserSession(
        mode: EraserMode.area,
        radius: 6,
        strokes: [_line('a', 0)],
        nextId: () => 'frag-${seq++}',
      );
      session.eraseAt(const Offset(30, 0));
      session.eraseAt(const Offset(70, 0));
      final result = session.commit();
      // Original removed once; surviving fragments only.
      expect(result.removed.map((s) => s.id), ['a']);
      expect(result.added.length, session.visibleStrokes.length);
      for (final frag in result.added) {
        for (final p in frag.points) {
          expect((p.x - 30).abs() > 6 - 1.5 || (p.x - 70).abs() > 6 - 1.5,
              isTrue);
        }
      }
    });
  });

  group('LassoEngine', () {
    final square = [
      const Offset(0, 0),
      const Offset(100, 0),
      const Offset(100, 100),
      const Offset(0, 100),
    ];

    test('pointInPolygon basic containment', () {
      expect(LassoEngine.pointInPolygon(const Offset(50, 50), square), isTrue);
      expect(
          LassoEngine.pointInPolygon(const Offset(150, 50), square), isFalse);
    });

    test('stroke mostly inside is selected; mostly outside is not', () {
      final inside = _line('in', 50, x0: 10, x1: 90);
      final crossing = _line('out', 50, x0: 80, x1: 300);
      final result = LassoEngine.select(
        polygon: square,
        strokes: [inside, crossing],
        images: const [],
      );
      expect(result.strokeIds, {'in'});
    });

    test('selects an image only when no strokes were caught', () {
      const image = ImageObject(
          id: 'img', assetPath: 'x', x: 20, y: 20, width: 40, height: 40);
      final empty = LassoEngine.select(
          polygon: square, strokes: const [], images: const [image]);
      expect(empty.imageId, 'img');

      final withStroke = LassoEngine.select(
        polygon: square,
        strokes: [_line('s', 50, x0: 10, x1: 90)],
        images: const [image],
      );
      expect(withStroke.strokeIds, {'s'});
      expect(withStroke.imageId, isNull);
    });

    test('selectionBounds unions stroke bounds', () {
      final bounds = LassoEngine.selectionBounds(
          [_line('a', 0), _line('b', 100)]);
      expect(bounds!.top, lessThanOrEqualTo(0));
      expect(bounds.bottom, greaterThanOrEqualTo(100));
    });
  });

  group('StrokePathCache', () {
    test('rebuilds the path when a lasso transform moves the stroke', () {
      final cache = StrokePathCache();
      final stroke = _line('a', 50);
      final original = cache.of(stroke);

      // Lasso move keeps the id but rewrites the geometry.
      final moved = transformStroke(stroke, offset: const Offset(40, 30));
      final movedPath = cache.of(moved);

      expect(movedPath.getBounds().center.dx,
          closeTo(original.getBounds().center.dx + 40, 1));
      expect(movedPath.getBounds().center.dy,
          closeTo(original.getBounds().center.dy + 30, 1));
      // Undoing the move (same id, original geometry) lands back.
      expect(cache.of(stroke).getBounds().center.dx,
          closeTo(original.getBounds().center.dx, 1));
    });

    test('recolor stays a cache hit (points list is reused)', () {
      final cache = StrokePathCache();
      final stroke = _line('a', 50);
      final path = cache.of(stroke);
      final recolored = stroke.copyWith(color: const Color(0xFFFF0000));
      expect(identical(cache.of(recolored), path), isTrue);
    });
  });
}
