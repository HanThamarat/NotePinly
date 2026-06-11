import 'dart:ui';

import '../../../domain/entities/note_document.dart';

/// Vertical stack of all pages in document display coordinates: pages are
/// centered horizontally and separated by [gap]. This is what makes the
/// note one continuous scroll surface (GoodNotes-style) instead of a
/// page-at-a-time view.
class DocumentLayout {
  DocumentLayout(List<NotePage> pages, {this.gap = 24.0}) {
    var maxWidth = 0.0;
    for (final page in pages) {
      maxWidth = maxWidth < page.spec.displayWidth
          ? page.spec.displayWidth
          : maxWidth;
    }
    var y = 0.0;
    pageRects = List.unmodifiable([
      for (final page in pages)
        () {
          final w = page.spec.displayWidth;
          final h = page.spec.displayHeight;
          final rect = Rect.fromLTWH((maxWidth - w) / 2, y, w, h);
          y += h + gap;
          return rect;
        }(),
    ]);
    size = Size(maxWidth, y - (pageRects.isEmpty ? 0 : gap));
  }

  final double gap;

  /// One rect per page, top to bottom, in document display coordinates.
  late final List<Rect> pageRects;

  /// Total document extent (no outer margins; the camera adds those).
  late final Size size;

  /// Index of the page containing [point], or -1 for gaps and backdrop.
  int pageAt(Offset point) {
    for (var i = 0; i < pageRects.length; i++) {
      if (pageRects[i].contains(point)) return i;
    }
    return -1;
  }

  /// The page whose vertical span is closest to [y] — drives the
  /// "current page" indicator while scrolling.
  int nearestPageTo(double y) {
    if (pageRects.isEmpty) return 0;
    var best = 0;
    var bestDistance = double.infinity;
    for (var i = 0; i < pageRects.length; i++) {
      final rect = pageRects[i];
      final d = y < rect.top
          ? rect.top - y
          : (y > rect.bottom ? y - rect.bottom : 0.0);
      if (d < bestDistance) {
        bestDistance = d;
        best = i;
      }
      if (d == 0) break;
    }
    return best;
  }

  /// Inclusive index range of pages intersecting the vertical document
  /// span [topY, bottomY]; (0, -1) when nothing is visible.
  (int, int) visibleRange(double topY, double bottomY) {
    var first = -1;
    var last = -2;
    for (var i = 0; i < pageRects.length; i++) {
      final rect = pageRects[i];
      if (rect.bottom < topY) continue;
      if (rect.top > bottomY) break;
      if (first < 0) first = i;
      last = i;
    }
    return first < 0 ? (0, -1) : (first, last);
  }
}
