import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:notepinly/domain/entities/page_spec.dart';
import 'package:notepinly/domain/entities/stroke.dart';
import 'package:notepinly/presentation/editor/engine/one_euro_filter.dart';
import 'package:notepinly/presentation/editor/engine/page_camera.dart';
import 'package:notepinly/presentation/editor/engine/page_transform.dart';
import 'package:notepinly/presentation/editor/engine/ribbon_builder.dart';

void main() {
  group('OneEuroFilter', () {
    test('passes the first sample through unchanged', () {
      final f = OneEuroFilter();
      expect(f.filter(42.0, 0), 42.0);
    });

    test('smooths jitter around a constant value', () {
      final f = OneEuroFilter();
      final noisy = [10.0, 10.4, 9.7, 10.3, 9.8, 10.2, 9.9, 10.1];
      double last = 0;
      for (var i = 0; i < noisy.length; i++) {
        last = f.filter(noisy[i], i * 8);
      }
      // Filtered output should sit much closer to 10 than the raw jitter.
      expect((last - 10.0).abs(), lessThan(0.2));
    });

    test('tracks fast movement without large lag', () {
      final f = OneEuroFilter();
      double last = 0;
      for (var i = 0; i <= 20; i++) {
        last = f.filter(i * 10.0, i * 8); // 10px per 8ms — a fast stroke
      }
      // Should stay within a few px of the raw position at speed.
      expect((last - 200.0).abs(), lessThan(15));
    });
  });

  group('RibbonBuilder', () {
    Stroke line({double p1 = 0.5, double p2 = 0.5, double width = 4}) =>
        Stroke(
          id: 'l',
          color: const Color(0xFF000000),
          baseWidth: width,
          points: [
            StrokePoint(x: 0, y: 0, pressure: p1, timestampMs: 0),
            StrokePoint(x: 50, y: 0, pressure: (p1 + p2) / 2, timestampMs: 8),
            StrokePoint(x: 100, y: 0, pressure: p2, timestampMs: 16),
          ],
        );

    test('single point renders as a dot', () {
      final stroke = Stroke(
        id: 'dot',
        color: const Color(0xFF000000),
        baseWidth: 6,
        points: const [
          StrokePoint(x: 5, y: 5, pressure: 1, timestampMs: 0),
        ],
      );
      final path = RibbonBuilder.build(stroke);
      final b = path.getBounds();
      expect(b.center.dx, closeTo(5, 0.01));
      expect(b.width, closeTo(6, 0.01)); // full base width at pressure 1
    });

    test('width responds to pressure', () {
      final light = RibbonBuilder.build(line(p1: 0.1, p2: 0.1)).getBounds();
      final heavy = RibbonBuilder.build(line(p1: 1.0, p2: 1.0)).getBounds();
      expect(heavy.height, greaterThan(light.height));
      // Heavy = full base width; light = minWidthFactor floor.
      expect(heavy.height, closeTo(4, 0.3));
      expect(
        light.height,
        closeTo(4 * RibbonBuilder.minWidthFactor + 0.2, 0.6),
      );
    });

    test('covers the full stroke extent', () {
      final path = RibbonBuilder.build(line());
      final b = path.getBounds();
      expect(b.left, lessThanOrEqualTo(0));
      expect(b.right, greaterThanOrEqualTo(100));
      expect(path.contains(const Offset(50, 0)), isTrue);
    });

    test('pressure never collapses width to zero', () {
      final path = RibbonBuilder.build(line(p1: 0, p2: 0));
      expect(path.getBounds().height, greaterThan(0.5));
    });
  });

  group('PageCamera', () {
    PageCamera camera() {
      final c = PageCamera(initialContentSize: const Size(800, 1000));
      c.fitToViewport(const Size(1200, 800));
      return c;
    }

    test('fit centers the page and respects scale bounds', () {
      final c = camera();
      expect(c.scale, inInclusiveRange(PageCamera.minScale, PageCamera.maxScale));
      final left = c.displayToScreen(Offset.zero).dx;
      final right = c.displayToScreen(const Offset(800, 0)).dx;
      expect((1200 - right) - left, closeTo(0, 0.5)); // horizontally centered
    });

    test('screenToDisplay inverts displayToScreen', () {
      final c = camera();
      const p = Offset(123, 456);
      final roundTrip = c.screenToDisplay(c.displayToScreen(p));
      expect((roundTrip - p).distance, lessThan(1e-9));
    });

    test('zoom keeps the focal point fixed', () {
      final c = camera();
      const focal = Offset(600, 400);
      final before = c.screenToDisplay(focal);
      c.zoomBy(1.5, focal);
      final after = c.screenToDisplay(focal);
      expect((after - before).distance, lessThan(1e-6));
      expect(c.scale, greaterThan(0));
    });

    test('zoom clamps to bounds', () {
      final c = camera();
      c.zoomBy(1000, const Offset(0, 0));
      expect(c.scale, PageCamera.maxScale);
      c.zoomBy(1e-9, const Offset(0, 0));
      expect(c.scale, PageCamera.minScale);
    });

    test('pan cannot fling the page fully off-screen', () {
      final c = camera();
      c.panBy(const Offset(100000, 100000));
      final pageOrigin = c.displayToScreen(Offset.zero);
      expect(pageOrigin.dx, lessThanOrEqualTo(1200));
      expect(pageOrigin.dy, lessThanOrEqualTo(800));
      c.panBy(const Offset(-200000, -200000));
      final pageEnd = c.displayToScreen(const Offset(800, 1000));
      expect(pageEnd.dx, greaterThanOrEqualTo(0));
      expect(pageEnd.dy, greaterThanOrEqualTo(0));
    });

    PageCamera pagedCamera() {
      final c = PageCamera(
        initialContentSize: const Size(800, 1000),
        pageBound: true,
      );
      c.fitToViewport(const Size(1200, 800));
      return c;
    }

    test('page-bound camera locks a fitting page and refuses the pan', () {
      final c = pagedCamera();
      final before = c.offset;
      final unconsumed = c.panBy(const Offset(50, -80));
      expect(c.offset, before);
      expect(unconsumed, const Offset(50, -80));
    });

    test('page-bound camera scrolls to the page edge, then overscrolls', () {
      final c = pagedCamera();
      c.zoomBy(2, const Offset(600, 400)); // page now taller than viewport
      c.panBy(const Offset(0, -100000)); // hit the bottom edge
      final unconsumed = c.panBy(const Offset(0, -60));
      expect(unconsumed.dy, -60); // nothing left to scroll
      expect(c.displayToScreen(const Offset(0, 1000)).dy,
          closeTo(800 - PageCamera.pageMargin, 0.5));
    });

    test('snapToVerticalEdge lands at the top or bottom of the page', () {
      final c = pagedCamera();
      c.zoomBy(2, const Offset(600, 400));
      c.snapToVerticalEdge(top: true);
      expect(c.displayToScreen(Offset.zero).dy,
          closeTo(PageCamera.pageMargin, 1e-6));
      c.snapToVerticalEdge(top: false);
      expect(c.displayToScreen(const Offset(0, 1000)).dy,
          closeTo(800 - PageCamera.pageMargin, 1e-6));
    });
  });

  group('PageTransform', () {
    const spec = PageSpec(id: 'p', width: 800, height: 1000);

    test('rotation swaps the display size on odd quarter turns', () {
      expect(PageTransform(spec.copyWith(rotation: 1)).displaySize,
          const Size(1000, 800));
      expect(PageTransform(spec.copyWith(rotation: 2)).displaySize,
          const Size(800, 1000));
    });

    test('displayToPage inverts pageToDisplay at every rotation', () {
      const point = Offset(120, 340);
      for (var q = 0; q < 4; q++) {
        final t = PageTransform(spec.copyWith(rotation: q));
        final roundTrip = t.displayToPage(t.pageToDisplay(point));
        expect((roundTrip - point).distance, lessThan(1e-9),
            reason: 'rotation $q');
      }
    });

    test('90° maps the page origin to the display top-right', () {
      final t = PageTransform(spec.copyWith(rotation: 1));
      expect(t.pageToDisplay(Offset.zero), const Offset(1000, 0));
      expect(t.pageToDisplay(const Offset(0, 1000)), Offset.zero);
    });
  });

  group('RibbonBuilder.widthFor', () {
    test('maps pressure linearly between floor and full width', () {
      expect(RibbonBuilder.widthFor(0, 10),
          closeTo(10 * RibbonBuilder.minWidthFactor, 1e-9));
      expect(RibbonBuilder.widthFor(1, 10), closeTo(10, 1e-9));
      final mid = RibbonBuilder.widthFor(0.5, 10);
      expect(mid, greaterThan(10 * RibbonBuilder.minWidthFactor));
      expect(mid, lessThan(10));
    });

    test('clamps out-of-range pressure', () {
      expect(RibbonBuilder.widthFor(-1, 10), RibbonBuilder.widthFor(0, 10));
      expect(RibbonBuilder.widthFor(math.e, 10), RibbonBuilder.widthFor(1, 10));
    });
  });
}
