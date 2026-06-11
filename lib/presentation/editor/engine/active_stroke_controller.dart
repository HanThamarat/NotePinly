import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../../domain/entities/stroke.dart';
import 'one_euro_filter.dart';
import 'ribbon_builder.dart';

/// Holds the stroke currently being drawn. This is the 120Hz hot path:
/// it lives entirely outside bloc state and notifies only the
/// active-stroke painter.
///
/// Geometry strategy: each accepted sample appends a stamped segment
/// (trapezoid + round joint) to a persistent [Path], so per-frame cost is
/// O(new samples), not O(stroke length). Ink is opaque, so the overlap
/// between stamps is invisible. On [end], the pretty Catmull-Rom ribbon is
/// built once for the committed layer.
class ActiveStrokeController extends ChangeNotifier {
  final _filterX = OneEuroFilter();
  final _filterY = OneEuroFilter();
  // Pressure gets a gentler filter: digitizer pressure is noisy and width
  // flicker is more visible than position jitter.
  final _filterP = OneEuroFilter(minCutoff: 0.6, beta: 0.005);

  final List<StrokePoint> _points = [];
  final Path _path = Path();
  Offset? _lastPos;
  double _lastHalfWidth = 0;
  Offset _velocity = Offset.zero; // logical px per ms
  int? _lastTimeMs;
  Duration? _startTimeStamp;

  Color _color = const Color(0xFF000000);
  double _baseWidth = 3.5;
  bool _active = false;

  bool get isActive => _active;
  Color get color => _color;

  /// The accumulated stamped path, in page coordinates.
  Path get path => _path;

  /// Short predicted tail ahead of the last real sample, rebuilt each
  /// sample from current velocity to hide one frame of latency.
  Path? get predictedTail {
    final last = _lastPos;
    if (!_active || last == null) return null;
    final speed = _velocity.distance; // px/ms
    if (speed < 0.05) return null;
    // Predict ~8ms ahead, capped so mispredictions stay subtle.
    final lookAheadMs = math.min(8.0, 4.0 / speed + 2.0);
    final tip = last + _velocity * lookAheadMs;
    return Path()
      ..moveTo(last.dx, last.dy)
      ..lineTo(tip.dx, tip.dy);
  }

  double get predictedTailWidth => _lastHalfWidth * 2;

  /// [timeStamp] is the pointer event's timestamp — hardware input time,
  /// not wall clock, so coalesced samples filter correctly.
  void start({
    required Offset pagePoint,
    required double pressure,
    double? tilt,
    required Duration timeStamp,
    required Color color,
    required double baseWidth,
  }) {
    _reset();
    _active = true;
    _color = color;
    _baseWidth = baseWidth;
    _startTimeStamp = timeStamp;
    _append(pagePoint, pressure, tilt, 0);
    notifyListeners();
  }

  void addSample({
    required Offset pagePoint,
    required double pressure,
    double? tilt,
    required Duration timeStamp,
  }) {
    if (!_active) return;
    final t = (timeStamp - _startTimeStamp!).inMilliseconds;
    _append(pagePoint, pressure, tilt, t);
    notifyListeners();
  }

  /// Finishes the stroke and returns it, or null for degenerate input.
  Stroke? end({required String id}) {
    if (!_active) return null;
    final stroke = _points.isEmpty
        ? null
        : Stroke(
            id: id,
            color: _color,
            baseWidth: _baseWidth,
            points: List.unmodifiable(_points),
          );
    _reset();
    notifyListeners();
    return stroke;
  }

  /// Discards the stroke (palm-rejection cancel: a finger stroke that
  /// turned out to be the start of a two-finger gesture).
  void cancel() {
    if (!_active) return;
    _reset();
    notifyListeners();
  }

  void _append(Offset raw, double rawPressure, double? tilt, int timeMs) {
    final x = _filterX.filter(raw.dx, timeMs);
    final y = _filterY.filter(raw.dy, timeMs);
    final p = _filterP.filter(rawPressure.clamp(0.0, 1.0), timeMs);
    final pos = Offset(x, y);

    final last = _lastPos;
    final lastT = _lastTimeMs;
    if (last != null && lastT != null && timeMs > lastT) {
      // Exponentially-smoothed velocity for the prediction tail.
      final instant = (pos - last) / (timeMs - lastT).toDouble();
      _velocity = _velocity == Offset.zero
          ? instant
          : Offset.lerp(_velocity, instant, 0.4)!;
    }

    // Drop micro-movements that only add vertices.
    if (last != null && (pos - last).distanceSquared < 0.16) return;

    _points.add(StrokePoint(
      x: pos.dx,
      y: pos.dy,
      pressure: p,
      tilt: tilt,
      timestampMs: timeMs,
    ));

    final hw = math.max(RibbonBuilder.widthFor(p, _baseWidth) / 2, 0.35);
    if (last == null) {
      _path.addOval(Rect.fromCircle(center: pos, radius: hw));
    } else {
      _appendSegment(last, _lastHalfWidth, pos, hw);
    }
    _lastPos = pos;
    _lastHalfWidth = hw;
    _lastTimeMs = timeMs;
  }

  /// Trapezoid between the two samples plus a round joint at the new one.
  void _appendSegment(Offset a, double aHw, Offset b, double bHw) {
    var dir = b - a;
    if (dir.distanceSquared < 1e-12) return;
    final inv = 1 / dir.distance;
    final n = Offset(-dir.dy * inv, dir.dx * inv);
    _path
      ..moveTo(a.dx + n.dx * aHw, a.dy + n.dy * aHw)
      ..lineTo(b.dx + n.dx * bHw, b.dy + n.dy * bHw)
      ..lineTo(b.dx - n.dx * bHw, b.dy - n.dy * bHw)
      ..lineTo(a.dx - n.dx * aHw, a.dy - n.dy * aHw)
      ..close()
      ..addOval(Rect.fromCircle(center: b, radius: bHw));
  }

  void _reset() {
    _active = false;
    _points.clear();
    _path.reset();
    _lastPos = null;
    _lastHalfWidth = 0;
    _lastTimeMs = null;
    _startTimeStamp = null;
    _velocity = Offset.zero;
    _filterX.reset();
    _filterY.reset();
    _filterP.reset();
  }
}
