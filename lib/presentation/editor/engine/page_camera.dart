import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

/// Read-only view transform the painters consume:
/// `screen = display * scale + offset`. Implemented by the document
/// camera itself and by per-page portals onto it.
abstract class CameraView extends ChangeNotifier {
  double get scale;
  Offset get offset;

  Offset screenToDisplay(Offset screen) => (screen - offset) / scale;

  Offset displayToScreen(Offset display) => display * scale + offset;
}

/// View transform between document display coordinates (the stacked,
/// rotated pages) and screen coordinates.
class PageCamera extends CameraView {
  PageCamera({
    required Size initialContentSize,
    Size? initialFitSize,
    this.startAtActualSize = false,
    this.pageBound = false,
  })  : _contentSize = initialContentSize,
        _fitSize = initialFitSize ?? initialContentSize;

  /// Whiteboards open at 100% centered instead of fit-to-page.
  final bool startAtActualSize;

  /// Paged notes clamp the camera to the document bounds so leftover
  /// vertical pan can pull a new page in at the end; whiteboards keep the
  /// loose "sliver visible" clamp.
  final bool pageBound;

  static const double minScale = 0.1;
  static const double maxScale = 8.0;

  /// Backdrop breathing room around a page-bound camera.
  static const double pageMargin = 24.0;

  Size _contentSize;

  /// What the initial zoom fits to — the first page, not the whole
  /// document, which can be arbitrarily tall.
  final Size _fitSize;

  double _scale = 1;
  Offset _offset = Offset.zero;
  Size _viewport = Size.zero;
  bool _initialized = false;

  Size get contentSize => _contentSize;

  @override
  double get scale => _scale;

  @override
  Offset get offset => _offset;

  double get verticalOffset => _offset.dy;

  /// Document grew or a page rotated: keep the scroll position, adapt the
  /// bounds. (Whiteboards re-center; their content is a single page.)
  void setContentSize(Size size) {
    if (size == _contentSize) return;
    _contentSize = size;
    if (_initialized && !_viewport.isEmpty) {
      if (!pageBound) _centerContent();
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
              (viewport.width - pad) / _fitSize.width,
              (viewport.height - pad) / _fitSize.height,
            )
            .clamp(minScale, maxScale);
        _centerContent();
      }
      _initialized = true;
    } else if (!pageBound) {
      // Viewport resize: a free camera re-centers; a page-bound one keeps
      // its scroll position and just re-clamps.
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

  /// Pans and returns the part of [delta] the clamp swallowed; callers use
  /// the leftover vertical motion at the document end to add a page.
  Offset panBy(Offset delta) {
    final target = _offset + delta;
    _offset = target;
    _clampOffset();
    final unconsumed = target - _offset;
    notifyListeners();
    return unconsumed;
  }

  /// Programmatic scroll (page navigation); clamped like any pan.
  void setVerticalOffset(double dy) {
    if (dy == _offset.dy) return;
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

  /// Page-bound: the document never leaves its frame (fitting axes lock
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

/// One page's slice of the document camera: same zoom, offset shifted by
/// the page's origin in document display coordinates. Painters bound to a
/// portal draw in that page's local display space.
class PagePortal extends CameraView {
  PagePortal(this._camera) {
    _camera.addListener(notifyListeners);
  }

  final PageCamera _camera;

  /// Page top-left in document display coordinates; the layout updates
  /// this in place each build (painters read it at paint time).
  Offset origin = Offset.zero;

  @override
  double get scale => _camera.scale;

  @override
  Offset get offset => _camera.offset + origin * _camera.scale;

  @override
  void dispose() {
    _camera.removeListener(notifyListeners);
    super.dispose();
  }
}
