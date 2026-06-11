import 'dart:math' as math;
import 'dart:ui';

import '../../../domain/entities/stroke.dart';

enum EraserMode { stroke, area }

/// Pure eraser geometry. A drag becomes one [EraserSession]; the session
/// accumulates removed/added strokes so the whole drag is a single
/// undoable op.
abstract final class EraserEngine {
  /// True when the eraser circle touches the stroke's path (within the
  /// stroke's own half-width).
  static bool hits(Stroke stroke, Offset center, double radius) {
    final reach = radius + stroke.baseWidth / 2;
    if (!stroke.bounds.inflate(radius).contains(center)) return false;
    final pts = stroke.points;
    if (pts.length == 1) {
      return (Offset(pts[0].x, pts[0].y) - center).distance <= reach;
    }
    for (var i = 0; i < pts.length - 1; i++) {
      final a = Offset(pts[i].x, pts[i].y);
      final b = Offset(pts[i + 1].x, pts[i + 1].y);
      if (_segmentDistance(center, a, b) <= reach) return true;
    }
    return false;
  }

  /// Splits a stroke around the eraser circle. Returns the surviving
  /// fragments (each gets a fresh id); empty when fully erased.
  static List<Stroke> split(
    Stroke stroke,
    Offset center,
    double radius,
    String Function() nextId,
  ) {
    final reach = radius + stroke.baseWidth / 2;
    final fragments = <Stroke>[];
    var run = <StrokePoint>[];

    void flush() {
      // A single surviving point isn't drawable ink — drop it.
      if (run.length >= 2) {
        fragments.add(Stroke(
          id: nextId(),
          tool: stroke.tool,
          color: stroke.color,
          baseWidth: stroke.baseWidth,
          points: List.unmodifiable(run),
        ));
      }
      run = [];
    }

    for (final p in stroke.points) {
      final inside = (Offset(p.x, p.y) - center).distance <= reach;
      if (inside) {
        flush();
      } else {
        run.add(p);
      }
    }
    flush();
    return fragments;
  }

  static double _segmentDistance(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final lenSq = ab.distanceSquared;
    if (lenSq < 1e-12) return (p - a).distance;
    final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / lenSq).clamp(0.0, 1.0);
    return (p - (a + ab * t)).distance;
  }
}

/// Accumulates one eraser drag. Feed it the live stroke list view; commit
/// produces the removed/added lists for a single [EraseStrokesOp].
class EraserSession {
  EraserSession({
    required this.mode,
    required this.radius,
    required List<Stroke> strokes,
    required this.nextId,
  }) : _working = [...strokes];

  final EraserMode mode;
  final double radius;
  final String Function() nextId;

  final List<Stroke> _working;
  final Map<String, Stroke> _removedOriginals = {};
  final Set<String> _addedIds = {};

  /// Current visible strokes (originals minus erased, plus fragments).
  List<Stroke> get visibleStrokes => List.unmodifiable(_working);

  bool get isDirty => _removedOriginals.isNotEmpty;

  /// Applies the eraser at [center] (page coords). Returns true when
  /// anything changed, so the canvas can repaint.
  bool eraseAt(Offset center) {
    var changed = false;
    for (var i = _working.length - 1; i >= 0; i--) {
      final stroke = _working[i];
      if (!EraserEngine.hits(stroke, center, radius)) continue;
      changed = true;
      _noteRemoved(stroke);
      if (mode == EraserMode.stroke) {
        _working.removeAt(i);
      } else {
        final fragments = EraserEngine.split(stroke, center, radius, nextId);
        _working.removeAt(i);
        _working.insertAll(i, fragments);
        _addedIds.addAll(fragments.map((f) => f.id));
      }
    }
    return changed;
  }

  void _noteRemoved(Stroke stroke) {
    if (_addedIds.contains(stroke.id)) {
      // A fragment we created this session — not an original.
      _addedIds.remove(stroke.id);
      return;
    }
    _removedOriginals.putIfAbsent(stroke.id, () => stroke);
  }

  /// Removed originals and surviving fragments for the op.
  ({List<Stroke> removed, List<Stroke> added}) commit() {
    final added =
        [for (final s in _working) if (_addedIds.contains(s.id)) s];
    return (removed: _removedOriginals.values.toList(), added: added);
  }
}

/// Eraser size presets in page-logical pixels (radius).
const eraserSizePresets = <double>[6.0, 12.0, 24.0];

double clampEraserRadius(double r) => math.max(2, math.min(60, r));
