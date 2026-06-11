import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../../domain/services/pdf_renderer.dart';

/// Lazily rasterizes PDF pages for page backgrounds with a small LRU so
/// large PDFs never hold more than a few pages in memory. Rasters are
/// re-rendered at a coarse zoom bucket so zooming in stays sharp without
/// re-rendering on every pinch frame.
class PdfBackgroundCache extends ChangeNotifier {
  PdfBackgroundCache({required this.renderer, required this.pdfPath});

  final PdfRenderer renderer;
  final String pdfPath;

  static const _maxEntries = 6;

  PdfDocumentHandle? _doc;
  bool _opening = false;
  // Dart map literals preserve insertion order — that's the LRU order.
  final _images = <String, ui.Image>{};
  final _rendering = <String>{};

  /// Quantize camera scale to 1 / 2 / 4 so cache keys stay few.
  static double bucketFor(double cameraScale) =>
      cameraScale <= 1.2 ? 1 : (cameraScale <= 2.5 ? 2 : 4);

  ui.Image? pageImage(int pageIndex, double cameraScale) {
    final bucket = bucketFor(cameraScale);
    final key = '$pageIndex@$bucket';
    final hit = _images.remove(key);
    if (hit != null) {
      _images[key] = hit; // refresh LRU position
      return hit;
    }
    _request(pageIndex, bucket, key);
    // Any older bucket of the same page beats a blank background.
    for (final entry in _images.entries.toList().reversed) {
      if (entry.key.startsWith('$pageIndex@')) return entry.value;
    }
    return null;
  }

  Future<void> _request(int pageIndex, double bucket, String key) async {
    if (_rendering.contains(key)) return;
    _rendering.add(key);
    try {
      if (_doc == null) {
        if (_opening) return;
        _opening = true;
        _doc = await renderer.open(pdfPath);
        _opening = false;
      }
      final image = await _doc!.renderPage(pageIndex, bucket);
      _images[key] = image;
      while (_images.length > _maxEntries) {
        _images.remove(_images.keys.first)?.dispose();
      }
      notifyListeners();
    } catch (_) {
      // Render failure: page shows plain paper; retry on next request.
    } finally {
      _rendering.remove(key);
    }
  }

  @override
  void dispose() {
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
    _doc?.close();
    super.dispose();
  }
}
