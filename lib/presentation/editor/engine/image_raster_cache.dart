import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

/// Decodes image asset files into ui.Images on demand and notifies when
/// one becomes available. Painters request synchronously and repaint on
/// notification — no awaiting in the paint path.
class ImageRasterCache extends ChangeNotifier {
  final _images = <String, ui.Image>{};
  final _loading = <String>{};

  ui.Image? imageFor(String path) {
    final cached = _images[path];
    if (cached != null) return cached;
    if (_loading.add(path)) {
      _load(path);
    }
    return null;
  }

  Future<void> _load(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      _images[path] = frame.image;
      notifyListeners();
    } catch (_) {
      // Missing/corrupt asset: leave a blank slot rather than crash.
    } finally {
      _loading.remove(path);
    }
  }

  @override
  void dispose() {
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
    super.dispose();
  }
}
