import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../../../domain/entities/document_op.dart' show transformStroke;
import '../../../domain/entities/editor_tool.dart';
import '../../../domain/entities/image_object.dart';
import '../../../domain/entities/note_document.dart';
import '../../../domain/entities/stroke.dart';
import '../engine/active_stroke_controller.dart';
import '../engine/eraser_engine.dart';
import '../engine/image_raster_cache.dart';
import '../engine/lasso_engine.dart';
import '../engine/page_camera.dart';
import '../engine/page_transform.dart';
import '../engine/pdf_background_cache.dart';
import 'ink_painters.dart';
import 'overlay_painter.dart';

enum _DragKind {
  none,
  draw,
  erase,
  lasso,
  moveSelection,
  scaleSelection,
  moveImage,
  scaleImage,
}

/// The drawing surface: pointer routing for every tool, palm rejection,
/// and the five paint layers (paper, images, committed ink, active
/// stroke, overlay).
///
/// Input contract (PRODUCT.md principle 5):
/// - Stylus always operates the active tool; first stylus contact flips
///   the session into stylus mode and fingers stop drawing.
/// - Before stylus mode: one finger uses the tool, two fingers pan/zoom
///   (a young one-finger action is cancelled when the second lands).
/// - In stylus mode: one finger pans, two fingers pan/zoom.
/// - Inverted stylus or the S Pen barrel button force the eraser.
class InkCanvas extends StatefulWidget {
  const InkCanvas({
    super.key,
    required this.camera,
    required this.activeStroke,
    required this.page,
    required this.revision,
    required this.tool,
    required this.penColor,
    required this.penWidth,
    required this.eraserMode,
    required this.eraserRadius,
    required this.selectedStrokeIds,
    required this.selectedImageId,
    required this.imageCache,
    required this.onStrokeCommitted,
    required this.onErased,
    required this.onSelectionChanged,
    required this.onSelectionTransformed,
    required this.onImageTransformed,
    this.isWhiteboard = false,
    this.pdfCache,
    this.onZoomChanged,
    this.hasNextPage = false,
    this.hasPreviousPage = false,
    this.canAddPage = false,
    this.onPageSwitchRequested,
    this.onOverscrollChanged,
  });

  final PageCamera camera;
  final ActiveStrokeController activeStroke;
  final NotePage page;
  final int revision;
  final EditorTool tool;
  final Color penColor;
  final double penWidth;
  final EraserMode eraserMode;
  final double eraserRadius;
  final Set<String> selectedStrokeIds;
  final String? selectedImageId;
  final ImageRasterCache imageCache;
  final bool isWhiteboard;
  final PdfBackgroundCache? pdfCache;
  final ValueChanged<Stroke> onStrokeCommitted;
  final void Function(List<Stroke> removed, List<Stroke> added) onErased;
  final void Function(Set<String> strokeIds, String? imageId)
      onSelectionChanged;
  final void Function(List<Stroke> before, List<Stroke> after)
      onSelectionTransformed;
  final void Function(ImageObject before, ImageObject after)
      onImageTransformed;
  final ValueChanged<double>? onZoomChanged;

  /// Page-turn-by-scroll (GoodNotes style). Vertical pan left over at the
  /// page edge accumulates; past a threshold [onPageSwitchRequested] fires
  /// with +1 (next / new page) or -1 (previous page).
  final bool hasNextPage;
  final bool hasPreviousPage;
  final bool canAddPage;
  final ValueChanged<int>? onPageSwitchRequested;

  /// Progress toward a page turn in -1..1 (positive = forward); drives the
  /// hint chip the editor screen overlays.
  final ValueChanged<double>? onOverscrollChanged;

  @override
  State<InkCanvas> createState() => _InkCanvasState();
}

class _InkCanvasState extends State<InkCanvas> {
  final _pathCache = StrokePathCache();
  final _interaction = CanvasInteraction();

  bool _stylusSeen = false;
  int? _primaryPointer;
  bool _primaryIsTouch = false;
  Duration _dragStartedAt = Duration.zero;
  int _idSeq = 0;

  _DragKind _drag = _DragKind.none;
  EraserSession? _eraserSession;
  Offset _dragStartPage = Offset.zero;
  Offset _scalePivot = Offset.zero;
  double _scaleStartDistance = 1;
  List<Stroke> _dragBaseStrokes = const [];
  Set<String> _hiddenIds = const {};
  ImageObject? _imageBefore;
  Rect? _imageDragRect;
  int _imageHandle = -1;

  final _touches = <int, Offset>{};
  Offset? _gestureFocal;
  double? _gestureSpan;

  /// Pinch hysteresis: fingers land/move alternately so the span always
  /// jitters; only a ~4% deviation from the starting span means the user
  /// is actually zooming. Until then a two-finger drag is a pure pan.
  static const _pinchActivation = 0.04;
  double? _gestureStartSpan;
  bool _pinching = false;

  /// Leftover vertical pan at the page edge; ±[_pageTurnThreshold] turns
  /// the page. Negative = content pushed up = toward the next page.
  static const _pageTurnThreshold = 90.0;
  double _overscroll = 0;
  bool _overscrollArmed = true;
  DateTime _lastWheelAt = DateTime.fromMillisecondsSinceEpoch(0);

  PageTransform get _transform => PageTransform(widget.page.spec);

  @override
  void didUpdateWidget(InkCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision) {
      _pathCache.retainOnly(widget.page.strokes);
    }
    if (oldWidget.page.spec != widget.page.spec) {
      widget.camera.setContentSize(_transform.displaySize);
    }
    _syncSelectionVisuals();
  }

  @override
  void dispose() {
    _interaction.dispose();
    super.dispose();
  }

  void _syncSelectionVisuals() {
    final selected = [
      for (final s in widget.page.strokes)
        if (widget.selectedStrokeIds.contains(s.id)) s
    ];
    _interaction.selectionBounds = LassoEngine.selectionBounds(selected);
    ImageObject? image;
    for (final i in widget.page.images) {
      if (i.id == widget.selectedImageId) image = i;
    }
    _interaction.imageBounds = image?.rect;
    _interaction.eraserRadius = widget.eraserRadius;
  }

  String _nextId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_idSeq++}';

  Offset _toPage(Offset local) =>
      _transform.displayToPage(widget.camera.screenToDisplay(local));

  // --- Pointer routing ---

  bool _isDrawingDevice(PointerEvent e) =>
      e.kind == PointerDeviceKind.stylus ||
      e.kind == PointerDeviceKind.invertedStylus ||
      (e.kind == PointerDeviceKind.mouse && e.buttons & kPrimaryButton != 0);

  bool _forcesEraser(PointerEvent e) =>
      e.kind == PointerDeviceKind.invertedStylus ||
      (e.kind == PointerDeviceKind.stylus &&
          e.buttons & kPrimaryStylusButton != 0);

  void _onPointerDown(PointerDownEvent e) {
    if (_isDrawingDevice(e)) {
      if (e.kind != PointerDeviceKind.mouse) _stylusSeen = true;
      if (_primaryIsTouch) _cancelPrimaryAction();
      _touches.clear();
      _resetGestureBaseline();
      _beginPrimary(e, withTouch: false);
      return;
    }

    if (e.kind == PointerDeviceKind.touch) {
      _touches[e.pointer] = e.localPosition;
      if (_touches.length == 1) {
        if (!_stylusSeen && _primaryPointer == null) {
          _beginPrimary(e, withTouch: true);
        } else {
          _resetGestureBaseline();
        }
      } else if (_touches.length == 2 && _primaryIsTouch) {
        final ageMs = (e.timeStamp - _dragStartedAt).inMilliseconds;
        if (ageMs < 250) {
          _cancelPrimaryAction();
        } else {
          _finishPrimaryAction(e.localPosition);
        }
        _resetGestureBaseline();
      } else {
        _resetGestureBaseline();
      }
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (e.pointer == _primaryPointer) {
      _movePrimary(e);
      return;
    }
    if (_touches.containsKey(e.pointer)) {
      _touches[e.pointer] = e.localPosition;
      _updateGesture();
    }
  }

  void _onPointerUp(PointerEvent e) {
    if (e.pointer == _primaryPointer) {
      _finishPrimaryAction(e.localPosition);
      return;
    }
    if (_touches.remove(e.pointer) != null) _resetGestureBaseline();
  }

  void _onPointerCancel(PointerCancelEvent e) {
    if (e.pointer == _primaryPointer) {
      _cancelPrimaryAction();
      return;
    }
    if (_touches.remove(e.pointer) != null) _resetGestureBaseline();
  }

  // --- Primary (tool) action ---

  void _beginPrimary(PointerDownEvent e, {required bool withTouch}) {
    _primaryPointer = e.pointer;
    _primaryIsTouch = withTouch;
    _dragStartedAt = e.timeStamp;
    final page = _toPage(e.localPosition);

    final tool = _forcesEraser(e) ? EditorTool.eraser : widget.tool;
    switch (tool) {
      case EditorTool.pen:
        _drag = _DragKind.draw;
        widget.activeStroke.start(
          pagePoint: page,
          pressure: _normalizedPressure(e),
          tilt: e.kind == PointerDeviceKind.stylus ? e.tilt : null,
          timeStamp: e.timeStamp,
          color: widget.penColor,
          baseWidth: widget.penWidth,
        );
      case EditorTool.eraser:
        _drag = _DragKind.erase;
        _eraserSession = EraserSession(
          mode: widget.eraserMode,
          radius: widget.eraserRadius,
          strokes: widget.page.strokes,
          nextId: _nextId,
        );
        _interaction.update(() {
          _interaction.eraserVisible = true;
          _interaction.eraserCursor = widget.camera.screenToDisplay(e.localPosition);
        });
        if (_eraserSession!.eraseAt(page)) setState(() {});
      case EditorTool.lasso:
        _beginLassoInteraction(page);
    }
  }

  void _beginLassoInteraction(Offset page) {
    final onePx = 1 / widget.camera.scale;
    final grab = selectionHandleRadius * onePx * 2.2;

    // Scale handles on a stroke selection.
    final bounds = _interaction.selectionBounds;
    if (bounds != null) {
      final outer = bounds.inflate(6 * onePx);
      final corners = handlePositions(outer);
      for (var i = 0; i < corners.length; i++) {
        if ((corners[i] - page).distance <= grab) {
          _startSelectionDrag(_DragKind.scaleSelection, page,
              pivot: corners[(i + 2) % 4]);
          return;
        }
      }
      if (outer.contains(page)) {
        _startSelectionDrag(_DragKind.moveSelection, page,
            pivot: bounds.center);
        return;
      }
    }

    // Handles / body of a selected image.
    final imageRect = _interaction.imageBounds;
    if (imageRect != null && widget.selectedImageId != null) {
      final outer = imageRect.inflate(6 * onePx);
      final corners = handlePositions(outer);
      for (var i = 0; i < corners.length; i++) {
        if ((corners[i] - page).distance <= grab) {
          _drag = _DragKind.scaleImage;
          _imageHandle = i;
          _imageBefore = widget.page.images
              .firstWhere((img) => img.id == widget.selectedImageId);
          _imageDragRect = _imageBefore!.rect;
          _dragStartPage = page;
          return;
        }
      }
      if (outer.contains(page)) {
        _drag = _DragKind.moveImage;
        _imageBefore = widget.page.images
            .firstWhere((img) => img.id == widget.selectedImageId);
        _imageDragRect = _imageBefore!.rect;
        _dragStartPage = page;
        return;
      }
    }

    // Fresh lasso.
    _drag = _DragKind.lasso;
    _interaction.update(() => _interaction.lassoPoints = [page]);
  }

  void _startSelectionDrag(_DragKind kind, Offset page,
      {required Offset pivot}) {
    _drag = kind;
    _dragStartPage = page;
    _scalePivot = pivot;
    _scaleStartDistance = math.max((page - pivot).distance, 1e-3);
    _dragBaseStrokes = [
      for (final s in widget.page.strokes)
        if (widget.selectedStrokeIds.contains(s.id)) s
    ];
    setState(() => _hiddenIds = {for (final s in _dragBaseStrokes) s.id});
    _interaction.update(() {
      _interaction.draggedStrokes = _dragBaseStrokes;
      _interaction.dragPivot = _scalePivot;
      _interaction.dragOffset = Offset.zero;
      _interaction.dragScale = 1;
    });
  }

  void _movePrimary(PointerMoveEvent e) {
    final page = _toPage(e.localPosition);
    switch (_drag) {
      case _DragKind.draw:
        widget.activeStroke.addSample(
          pagePoint: page,
          pressure: _normalizedPressure(e),
          tilt: e.kind == PointerDeviceKind.stylus ? e.tilt : null,
          timeStamp: e.timeStamp,
        );
      case _DragKind.erase:
        _interaction.update(() => _interaction.eraserCursor =
            widget.camera.screenToDisplay(e.localPosition));
        if (_eraserSession?.eraseAt(page) ?? false) setState(() {});
      case _DragKind.lasso:
        _interaction.update(() => _interaction.lassoPoints.add(page));
      case _DragKind.moveSelection:
        _interaction.update(
            () => _interaction.dragOffset = page - _dragStartPage);
      case _DragKind.scaleSelection:
        final scale = ((page - _scalePivot).distance / _scaleStartDistance)
            .clamp(0.2, 5.0);
        _interaction.update(() => _interaction.dragScale = scale);
      case _DragKind.moveImage:
        setState(() => _imageDragRect =
            _imageBefore!.rect.shift(page - _dragStartPage));
      case _DragKind.scaleImage:
        setState(() => _imageDragRect = _scaledImageRect(page));
      case _DragKind.none:
        break;
    }
  }

  Rect _scaledImageRect(Offset page) {
    final base = _imageBefore!.rect;
    // Opposite corner stays fixed; aspect ratio preserved.
    final fixed = handlePositions(base)[(_imageHandle + 2) % 4];
    final w = (page.dx - fixed.dx).abs().clamp(24.0, double.infinity);
    final h = (page.dy - fixed.dy).abs().clamp(24.0, double.infinity);
    final ratio = base.width / base.height;
    final useWidth = w / ratio >= h;
    final width = useWidth ? w : h * ratio;
    final height = useWidth ? w / ratio : h;
    return Rect.fromLTWH(
      page.dx >= fixed.dx ? fixed.dx : fixed.dx - width,
      page.dy >= fixed.dy ? fixed.dy : fixed.dy - height,
      width,
      height,
    );
  }

  void _finishPrimaryAction(Offset localPosition) {
    switch (_drag) {
      case _DragKind.draw:
        final stroke = widget.activeStroke.end(id: _nextId());
        if (stroke != null) widget.onStrokeCommitted(stroke);
      case _DragKind.erase:
        final session = _eraserSession;
        if (session != null && session.isDirty) {
          final result = session.commit();
          widget.onErased(result.removed, result.added);
        }
        _eraserSession = null;
        _interaction.clearTransient();
        setState(() {});
      case _DragKind.lasso:
        _finishLasso(localPosition);
      case _DragKind.moveSelection:
      case _DragKind.scaleSelection:
        final after = [
          for (final s in _dragBaseStrokes)
            transformStroke(
              s,
              offset: _interaction.dragOffset,
              scale: _interaction.dragScale,
              pivot: _scalePivot,
            ),
        ];
        widget.onSelectionTransformed(_dragBaseStrokes, after);
        _dragBaseStrokes = const [];
        setState(() => _hiddenIds = const {});
        _interaction.clearTransient();
      case _DragKind.moveImage:
      case _DragKind.scaleImage:
        if (_imageBefore != null && _imageDragRect != null) {
          widget.onImageTransformed(
              _imageBefore!, _imageBefore!.withRect(_imageDragRect!));
        }
        setState(() {
          _imageBefore = null;
          _imageDragRect = null;
        });
      case _DragKind.none:
        break;
    }
    _drag = _DragKind.none;
    _primaryPointer = null;
    _primaryIsTouch = false;
  }

  void _finishLasso(Offset localPosition) {
    final pts = _interaction.lassoPoints;
    Rect extent = Rect.zero;
    if (pts.isNotEmpty) {
      extent = Rect.fromPoints(pts.first, pts.first);
      for (final p in pts) {
        extent = extent.expandToInclude(Rect.fromPoints(p, p));
      }
    }
    final isTap = extent.longestSide < 6;
    if (isTap) {
      // Tap: select the topmost image under the finger, or clear.
      final page = _toPage(localPosition);
      String? imageId;
      for (final img in widget.page.images.reversed) {
        if (img.rect.contains(page)) {
          imageId = img.id;
          break;
        }
      }
      widget.onSelectionChanged(const {}, imageId);
    } else {
      final result = LassoEngine.select(
        polygon: pts,
        strokes: widget.page.strokes,
        images: widget.page.images,
      );
      widget.onSelectionChanged(result.strokeIds, result.imageId);
    }
    _interaction.clearTransient();
  }

  void _cancelPrimaryAction() {
    switch (_drag) {
      case _DragKind.draw:
        widget.activeStroke.cancel();
      case _DragKind.erase:
        _eraserSession = null;
        _interaction.clearTransient();
        setState(() {});
      case _DragKind.lasso:
      case _DragKind.moveSelection:
      case _DragKind.scaleSelection:
        _dragBaseStrokes = const [];
        setState(() => _hiddenIds = const {});
        _interaction.clearTransient();
      case _DragKind.moveImage:
      case _DragKind.scaleImage:
        setState(() {
          _imageBefore = null;
          _imageDragRect = null;
        });
      case _DragKind.none:
        break;
    }
    _drag = _DragKind.none;
    _primaryPointer = null;
    _primaryIsTouch = false;
  }

  double _normalizedPressure(PointerEvent e) {
    final range = e.pressureMax - e.pressureMin;
    if (range <= 0) return 0.5;
    return ((e.pressure - e.pressureMin) / range).clamp(0.0, 1.0);
  }

  // --- Page-turn overscroll ---

  bool get _pagingEnabled =>
      !widget.isWhiteboard && widget.onPageSwitchRequested != null;

  bool _canPage(int direction) => direction > 0
      ? widget.hasNextPage || widget.canAddPage
      : widget.hasPreviousPage;

  void _setOverscroll(double value) {
    if (value == _overscroll) return;
    _overscroll = value;
    widget.onOverscrollChanged
        ?.call((-_overscroll / _pageTurnThreshold).clamp(-1.0, 1.0));
  }

  /// [unconsumed] is what the camera clamp refused. Any actual scroll
  /// resets the gauge; pure overscroll in a turnable direction charges it.
  void _trackOverscroll(Offset requested, Offset unconsumed) {
    if (!_pagingEnabled) return;
    if ((requested.dy - unconsumed.dy).abs() > 0.5) {
      _setOverscroll(0);
      return;
    }
    if (!_overscrollArmed) return;
    final next = _overscroll + unconsumed.dy;
    if (!_canPage(next < 0 ? 1 : -1)) {
      _setOverscroll(0);
      return;
    }
    _setOverscroll(next);
    if (next.abs() < _pageTurnThreshold) return;
    final direction = next < 0 ? 1 : -1;
    _overscrollArmed = false;
    _setOverscroll(0);
    widget.onPageSwitchRequested!(direction);
  }

  // --- Two-finger pan/zoom ---

  void _resetGestureBaseline() {
    _gestureFocal = _touches.isEmpty
        ? null
        : _touches.values.reduce((a, b) => a + b) / _touches.length.toDouble();
    _gestureSpan = _currentSpan();
    _gestureStartSpan = _gestureSpan;
    _pinching = false;
    if (_touches.isEmpty) {
      _overscrollArmed = true;
      _setOverscroll(0);
    }
  }

  double? _currentSpan() {
    if (_touches.length < 2) return null;
    final pts = _touches.values.toList();
    return (pts[0] - pts[1]).distance;
  }

  void _updateGesture() {
    if (_touches.isEmpty || _primaryIsTouch) return;
    final focal =
        _touches.values.reduce((a, b) => a + b) / _touches.length.toDouble();
    final span = _currentSpan();
    final prevSpan = _gestureSpan;
    final startSpan = _gestureStartSpan;
    if (!_pinching &&
        span != null &&
        startSpan != null &&
        startSpan > 0 &&
        (span / startSpan - 1).abs() > _pinchActivation) {
      _pinching = true;
    }
    if (_pinching && span != null && prevSpan != null && prevSpan > 0) {
      final factor = span / prevSpan;
      if ((factor - 1).abs() > 0.001) {
        widget.camera.zoomBy(factor, focal);
        widget.onZoomChanged?.call(widget.camera.scale);
      }
    }
    final prevFocal = _gestureFocal;
    if (prevFocal != null) {
      final delta = focal - prevFocal;
      final unconsumed = widget.camera.panBy(delta);
      // A pinch jiggles the focal point; never charge a page turn from it.
      if (_pinching) {
        _setOverscroll(0);
      } else {
        _trackOverscroll(delta, unconsumed);
      }
    }
    _gestureFocal = focal;
    _gestureSpan = span;
  }

  /// Desktop mouse wheel / trackpad: scrolls the page, and keeps scrolling
  /// past the edge to turn it. Momentum can't chain page turns — the gauge
  /// re-arms only after half a second of wheel silence.
  void _onPointerSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    final now = DateTime.now();
    if (now.difference(_lastWheelAt) > const Duration(milliseconds: 500)) {
      _overscrollArmed = true;
      _setOverscroll(0);
    }
    _lastWheelAt = now;
    final delta = Offset(-e.scrollDelta.dx, -e.scrollDelta.dy);
    final unconsumed = widget.camera.panBy(delta);
    _trackOverscroll(delta, unconsumed);
  }

  @override
  Widget build(BuildContext context) {
    _syncSelectionVisuals();
    final spec = widget.page.spec;
    final strokes =
        _eraserSession?.visibleStrokes ?? widget.page.strokes;
    final imageOverrides = <String, Rect>{
      if (_imageDragRect != null && _imageBefore != null)
        _imageBefore!.id: _imageDragRect!,
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        widget.camera.fitToViewport(
          Size(constraints.maxWidth, math.max(constraints.maxHeight, 1)),
        );
        return Listener(
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerCancel,
          onPointerSignal: _onPointerSignal,
          behavior: HitTestBehavior.opaque,
          child: ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                RepaintBoundary(
                  child: CustomPaint(
                    painter: PaperPainter(
                      camera: widget.camera,
                      spec: spec,
                      isWhiteboard: widget.isWhiteboard,
                      pdfCache: widget.pdfCache,
                    ),
                  ),
                ),
                RepaintBoundary(
                  child: CustomPaint(
                    painter: ImagesPainter(
                      camera: widget.camera,
                      spec: spec,
                      images: widget.page.images,
                      cache: widget.imageCache,
                      overrideRects: imageOverrides,
                    ),
                  ),
                ),
                RepaintBoundary(
                  child: CustomPaint(
                    painter: CommittedInkPainter(
                      camera: widget.camera,
                      spec: spec,
                      strokes: strokes,
                      revision: widget.revision,
                      cache: _pathCache,
                      hiddenIds: _hiddenIds,
                      clipToPage: !widget.isWhiteboard,
                    ),
                  ),
                ),
                RepaintBoundary(
                  child: CustomPaint(
                    painter: ActiveStrokePainter(
                      camera: widget.camera,
                      spec: spec,
                      controller: widget.activeStroke,
                      clipToPage: !widget.isWhiteboard,
                    ),
                  ),
                ),
                RepaintBoundary(
                  child: CustomPaint(
                    painter: OverlayPainter(
                      camera: widget.camera,
                      spec: spec,
                      interaction: _interaction,
                      pathCache: _pathCache,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
