import 'dart:math' as math;
import 'dart:ui' show Color, Rect;

import 'package:equatable/equatable.dart';

/// One input sample of a stroke, in page-local logical coordinates
/// (origin top-left of the page, pre-rotation, device-independent).
class StrokePoint extends Equatable {
  const StrokePoint({
    required this.x,
    required this.y,
    required this.pressure,
    this.tilt,
    required this.timestampMs,
  });

  final double x;
  final double y;

  /// Normalized 0..1. Mice and unsupported digitizers report 0.5.
  final double pressure;

  /// Radians from the surface normal, when the digitizer reports it.
  final double? tilt;

  /// Milliseconds since the stroke began.
  final int timestampMs;

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'p': pressure,
        if (tilt != null) 't': tilt,
        'ts': timestampMs,
      };

  factory StrokePoint.fromJson(Map<String, dynamic> json) => StrokePoint(
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        pressure: (json['p'] as num).toDouble(),
        tilt: (json['t'] as num?)?.toDouble(),
        timestampMs: (json['ts'] as num).toInt(),
      );

  @override
  List<Object?> get props => [x, y, pressure, tilt, timestampMs];
}

enum StrokeTool { pen }

/// A completed, immutable stroke. The vector data here is the source of
/// truth for everything downstream: rendering, lasso hit-testing,
/// recoloring, erasing, and persistence. Rasters are caches only.
class Stroke extends Equatable {
  Stroke({
    required this.id,
    this.tool = StrokeTool.pen,
    required this.color,
    required this.baseWidth,
    required this.points,
  }) : bounds = _computeBounds(points, baseWidth);

  final String id;
  final StrokeTool tool;
  final Color color;

  /// Full stroke width in logical pixels at pressure 1.0.
  final double baseWidth;
  final List<StrokePoint> points;

  /// Cached bounding box (inflated by the max half-width) for cheap
  /// culling and lasso prefiltering.
  final Rect bounds;

  static Rect _computeBounds(List<StrokePoint> points, double baseWidth) {
    if (points.isEmpty) return Rect.zero;
    var minX = double.infinity, minY = double.infinity;
    var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final p in points) {
      minX = math.min(minX, p.x);
      minY = math.min(minY, p.y);
      maxX = math.max(maxX, p.x);
      maxY = math.max(maxY, p.y);
    }
    final pad = baseWidth / 2;
    return Rect.fromLTRB(minX - pad, minY - pad, maxX + pad, maxY + pad);
  }

  Stroke copyWith({Color? color, List<StrokePoint>? points}) => Stroke(
        id: id,
        tool: tool,
        color: color ?? this.color,
        baseWidth: baseWidth,
        points: points ?? this.points,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'tool': tool.name,
        'color': _colorToArgb(color),
        'width': baseWidth,
        'points': [for (final p in points) p.toJson()],
      };

  factory Stroke.fromJson(Map<String, dynamic> json) => Stroke(
        id: json['id'] as String,
        tool: StrokeTool.values.byName(json['tool'] as String),
        color: Color(json['color'] as int),
        baseWidth: (json['width'] as num).toDouble(),
        points: [
          for (final p in json['points'] as List)
            StrokePoint.fromJson(p as Map<String, dynamic>),
        ],
      );

  static int _colorToArgb(Color c) =>
      (((c.a * 255).round() & 0xFF) << 24) |
      (((c.r * 255).round() & 0xFF) << 16) |
      (((c.g * 255).round() & 0xFF) << 8) |
      ((c.b * 255).round() & 0xFF);

  @override
  List<Object?> get props => [id, tool, color, baseWidth, points];
}
