import 'dart:math' as math;
import 'dart:ui';

import '../../../domain/entities/stroke.dart';

/// Builds the final filled-path geometry for a completed stroke:
/// Catmull-Rom interpolation through the captured points, pressure-mapped
/// variable width, round caps and joins.
///
/// The active (in-progress) stroke uses the cheaper incremental stamping in
/// [ActiveStrokeController]; this builder produces the committed version
/// rendered to the ink layer and reused for thumbnails later.
abstract final class RibbonBuilder {
  /// Spacing between interpolated samples, logical px.
  static const double _step = 2.0;

  /// Pressure 0 maps to this fraction of base width; pressure 1 to 1.0.
  static const double minWidthFactor = 0.35;

  static double widthFor(double pressure, double baseWidth) =>
      baseWidth * (minWidthFactor + (1 - minWidthFactor) * pressure.clamp(0, 1));

  static Path build(Stroke stroke) {
    final pts = stroke.points;
    final path = Path();
    if (pts.isEmpty) return path;
    if (pts.length == 1) {
      final w = widthFor(pts.first.pressure, stroke.baseWidth);
      path.addOval(Rect.fromCircle(
        center: Offset(pts.first.x, pts.first.y),
        radius: math.max(w / 2, 0.5),
      ));
      return path;
    }

    final samples = _resample(pts, stroke.baseWidth);
    return _ribbon(samples);
  }

  /// Catmull-Rom resampling: emits (position, halfWidth) samples spaced
  /// roughly [_step] apart along the curve.
  static List<(Offset, double)> _resample(
    List<StrokePoint> pts,
    double baseWidth,
  ) {
    final out = <(Offset, double)>[];
    for (var i = 0; i < pts.length - 1; i++) {
      final p0 = pts[math.max(i - 1, 0)];
      final p1 = pts[i];
      final p2 = pts[i + 1];
      final p3 = pts[math.min(i + 2, pts.length - 1)];

      final segLen =
          (Offset(p2.x, p2.y) - Offset(p1.x, p1.y)).distance;
      final steps = math.max(1, (segLen / _step).ceil());
      for (var s = 0; s < steps; s++) {
        final t = s / steps;
        out.add((
          _catmullRom(p0, p1, p2, p3, t),
          widthFor(_lerp(p1.pressure, p2.pressure, t), baseWidth) / 2,
        ));
      }
    }
    final last = pts.last;
    out.add((
      Offset(last.x, last.y),
      widthFor(last.pressure, baseWidth) / 2,
    ));
    return out;
  }

  static Offset _catmullRom(
    StrokePoint p0,
    StrokePoint p1,
    StrokePoint p2,
    StrokePoint p3,
    double t,
  ) {
    final t2 = t * t;
    final t3 = t2 * t;
    double comp(double v0, double v1, double v2, double v3) =>
        0.5 *
        ((2 * v1) +
            (-v0 + v2) * t +
            (2 * v0 - 5 * v1 + 4 * v2 - v3) * t2 +
            (-v0 + 3 * v1 - 3 * v2 + v3) * t3);
    return Offset(comp(p0.x, p1.x, p2.x, p3.x), comp(p0.y, p1.y, p2.y, p3.y));
  }

  /// Polygon outline: left edge forward, right edge back, round end caps.
  static Path _ribbon(List<(Offset, double)> samples) {
    final path = Path();
    if (samples.length < 2) {
      if (samples.isNotEmpty) {
        path.addOval(Rect.fromCircle(
          center: samples.first.$1,
          radius: math.max(samples.first.$2, 0.5),
        ));
      }
      return path;
    }

    final left = <Offset>[];
    final right = <Offset>[];
    for (var i = 0; i < samples.length; i++) {
      final (pos, hw) = samples[i];
      final prev = samples[math.max(i - 1, 0)].$1;
      final next = samples[math.min(i + 1, samples.length - 1)].$1;
      var tangent = next - prev;
      if (tangent.distanceSquared < 1e-12) tangent = const Offset(1, 0);
      final inv = 1 / tangent.distance;
      final normal = Offset(-tangent.dy * inv, tangent.dx * inv);
      final w = math.max(hw, 0.35);
      left.add(pos + normal * w);
      right.add(pos - normal * w);
    }

    // Right edge forward, left edge back: winds the same way as
    // [Path.addOval], so the cap ovals stack instead of cancelling under
    // the non-zero fill rule (opposite windings punch holes at the caps).
    path.moveTo(right.first.dx, right.first.dy);
    for (final p in right.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    for (final p in left.reversed) {
      path.lineTo(p.dx, p.dy);
    }
    path.close();

    // Round caps.
    path.addOval(Rect.fromCircle(
      center: samples.first.$1,
      radius: math.max(samples.first.$2, 0.35),
    ));
    path.addOval(Rect.fromCircle(
      center: samples.last.$1,
      radius: math.max(samples.last.$2, 0.35),
    ));
    return path;
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}
