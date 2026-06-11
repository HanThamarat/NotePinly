import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

/// View transform between display coordinates (the rotated page) and
/// screen coordinates: `screen = display * scale + offset`.
class PageCamera extends ChangeNotifier {
  PageCamera({
    required Size initialContentSize,
    this.startAtActualSize = false,
    this.pageBound = false,
  }) : _contentSize = initialContentSize;

  /// Whiteboards open at 100% centered instead of fit-to-page.
  final bool startAtActualSize;

  /// Paged notes clamp the camera to the page bounds so leftover vertical
  /// pan can turn pages; whiteboards keep the loose "sliver visible" clamp.
  final bool pageBound;

  static const double minScale = 0.1;
  static const double maxScale = 8.0;

  /// Backdrop breathing room around a page-bound camera.
  static const double pageMargin = 24.0;

  Size _contentSize;
  double _scale = 1;
  Offset _offset = Offset.zero;
  Size _viewport = Size.zero;
  bool _initialized = false;

  Size get contentSize => _contentSize;
  double get scale => _scale;
  Offset get offset => _offset;

  /// Page/rotation changed: keep the camera but adapt to the new size.
  void setContentSize(Size size) {
    if (size == _contentSize) return;
    _contentSize = size;
    if (_initialized && !_viewport.isEmpty) {
      _centerContent();
      _clampOffset();
      notifyListeners();
    }
  }

  /// Silent during build; painters read the camera at paint time.
  void fitToViewport(Size viewport) {
    if (viewport.isEmpty) return;
    final changed = viewport != _viewport;
    _viewport = viewport;
    if (_initialized && !changed) return;
    if (!_initialized) {
      if (startAtActualSize) {
        _scale = 1;
        _offset = Offset(
          viewport.width / 2 - _contentSize.width / 2,
          viewport.height / 2 - _contentSize.height / 2,
        );
      } else {
        const pad = 48.0;
        _scale = math
            .min(
              (viewport.width - pad) / _contentSize.width,
              (viewport.height - pad) / _contentSize.height,
            )
            .clamp(minScale, maxScale);
        _centerContent();
      }
      _initialized = true;
    } else {
      _centerContent();
    }
    _clampOffset();
    notifyListeners();
  }

  void _centerContent() {
    if (startAtActualSize) return;
    _offset = Offset(
      (_viewport.width - _contentSize.width * _scale) / 2,
      math.max((_viewport.height - _contentSize.height * _scale) / 2, 24),
    );
  }

  Offset screenToDisplay(Offset screen) => (screen - _offset) / _scale;

  Offset displayToScreen(Offset display) => display * _scale + _offset;

  /// Pans and returns the part of [delta] the clamp swallowed; callers use
  /// the leftover vertical motion to drive page turns.
  Offset panBy(Offset delta) {
    final target = _offset + delta;
    _offset = target;
    _clampOffset();
    final unconsumed = target - _offset;
    notifyListeners();
    return unconsumed;
  }

  /// Lands a page turn: arriving forward shows the top of the new page,
  /// going back shows the bottom of the previous one.
  void snapToVerticalEdge({required bool top}) {
    if (_viewport.isEmpty) return;
    final h = _contentSize.height * _scale;
    final dy = h + 2 * pageMargin <= _viewport.height
        ? (_viewport.height - h) / 2
        : (top ? pageMargin : _viewport.height - h - pageMargin);
    _offset = Offset(_offset.dx, dy);
    _clampOffset();
    notifyListeners();
  }

  void zoomBy(double factor, Offset focal) {
    final next = (_scale * factor).clamp(minScale, maxScale);
    if (next == _scale) return;
    _offset = focal - (focal - _offset) * (next / _scale);
    _scale = next;
    _clampOffset();
    notifyListeners();
  }

  /// Page-bound: the page never leaves its frame (fitting axes lock
  /// centered). Otherwise keeps at least a sliver of content on screen.
  void _clampOffset() {
    if (_viewport.isEmpty) return;
    final w = _contentSize.width * _scale;
    final h = _contentSize.height * _scale;
    if (pageBound) {
      _offset = Offset(
        _clampAxis(_offset.dx, w, _viewport.width),
        _clampAxis(_offset.dy, h, _viewport.height),
      );
      return;
    }
    const visible = 64.0;
    _offset = Offset(
      _offset.dx.clamp(visible - w, _viewport.width - visible),
      _offset.dy.clamp(visible - h, _viewport.height - visible),
    );
  }

  static double _clampAxis(double offset, double extent, double viewport) {
    if (extent + 2 * pageMargin <= viewport) return (viewport - extent) / 2;
    return offset.clamp(viewport - extent - pageMargin, pageMargin);
  }
}
