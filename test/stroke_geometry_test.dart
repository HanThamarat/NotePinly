import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:notepinly/domain/entities/stroke.dart';
import 'package:notepinly/presentation/editor/engine/active_stroke_controller.dart';
import 'package:notepinly/presentation/editor/engine/ribbon_builder.dart';

/// Regression tests for broken/holey ink: every point along the stroke
/// spine must be covered by the generated fill path. Holes appear when
/// subpaths (segment stamps, joint/cap ovals, the ribbon outline) wind in
/// opposite directions — the non-zero fill rule cancels the overlap.
List<Offset> _uncovered(Path path, List<Offset> spine) {
  final misses = <Offset>[];
  for (var i = 0; i < spine.length - 1; i++) {
    const sub = 8;
    for (var s = 0; s <= sub; s++) {
      final p = Offset.lerp(spine[i], spine[i + 1], s / sub)!;
      if (!path.contains(p)) misses.add(p);
    }
  }
  return misses;
}

Stroke _stroke(List<Offset> pts, {double Function(int)? pressure}) => Stroke(
      id: 'd',
      color: const Color(0xFF000000),
      baseWidth: 3.5,
      points: [
        for (var i = 0; i < pts.length; i++)
          StrokePoint(
            x: pts[i].dx,
            y: pts[i].dy,
            pressure: pressure?.call(i) ?? 0.5,
            timestampMs: i * 8,
          ),
      ],
    );

void main() {
  group('RibbonBuilder produces gap-free ink', () {
    test('straight line, both travel directions', () {
      final l2r = [for (var i = 0; i < 10; i++) Offset(10 + i * 10.0, 50)];
      final r2l = l2r.reversed.toList();
      expect(_uncovered(RibbonBuilder.build(_stroke(l2r)), l2r), isEmpty);
      expect(_uncovered(RibbonBuilder.build(_stroke(r2l)), r2l), isEmpty);
    });

    test('sharp cusp (hairpin turn)', () {
      final pts = [
        for (var i = 0; i <= 10; i++) Offset(10 + i * 8.0, 50),
        for (var i = 1; i <= 10; i++) Offset(90 - i * 8.0, 50 + i * 1.5),
      ];
      expect(_uncovered(RibbonBuilder.build(_stroke(pts)), pts), isEmpty);
    });

    test('zigzag handwriting-like curve', () {
      final pts = [
        for (var i = 0; i <= 40; i++)
          Offset(10 + i * 3.0, 50 + 18 * math.sin(i * 0.9)),
      ];
      expect(_uncovered(RibbonBuilder.build(_stroke(pts)), pts), isEmpty);
    });

    test('strongly varying pressure', () {
      final pts = [for (var i = 0; i < 20; i++) Offset(10 + i * 6.0, 50)];
      final stroke = _stroke(pts, pressure: (i) => i.isEven ? 0.1 : 0.9);
      expect(_uncovered(RibbonBuilder.build(stroke), pts), isEmpty);
    });
  });

  group('ActiveStrokeController stamped path is gap-free', () {
    test('straight run into a hairpin turn', () {
      final controller = ActiveStrokeController();
      final pts = [
        for (var i = 0; i <= 10; i++) Offset(10 + i * 8.0, 50),
        for (var i = 1; i <= 10; i++) Offset(90 - i * 8.0, 50 + i * 1.5),
      ];
      controller.start(
        pagePoint: pts.first,
        pressure: 0.5,
        timeStamp: Duration.zero,
        color: const Color(0xFF000000),
        baseWidth: 3.5,
      );
      for (var i = 1; i < pts.length; i++) {
        controller.addSample(
          pagePoint: pts[i],
          pressure: 0.5,
          timeStamp: Duration(milliseconds: i * 8),
        );
      }
      // Probe along the filtered spine the controller actually stamped.
      final spine = [
        for (final p in controller.debugPoints) Offset(p.x, p.y)
      ];
      expect(_uncovered(controller.path, spine), isEmpty);
      controller.end(id: 'x');
    });
  });
}
