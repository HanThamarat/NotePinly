import 'dart:ui' as ui;

import 'package:pdfx/pdfx.dart' as pdfx;

import '../../domain/services/pdf_renderer.dart';

/// Production PDF engine backed by the pdfx plugin (PDFKit on iOS,
/// PdfRenderer on Android).
class PdfxRenderer implements PdfRenderer {
  @override
  Future<PdfDocumentHandle> open(String path) async {
    final doc = await pdfx.PdfDocument.openFile(path);
    return _PdfxHandle(doc);
  }
}

class _PdfxHandle implements PdfDocumentHandle {
  _PdfxHandle(this._doc);

  final pdfx.PdfDocument _doc;

  @override
  int get pageCount => _doc.pagesCount;

  @override
  Future<ui.Size> pageSize(int pageIndex) async {
    final page = await _doc.getPage(pageIndex + 1);
    try {
      return ui.Size(page.width, page.height);
    } finally {
      await page.close();
    }
  }

  @override
  Future<ui.Image> renderPage(int pageIndex, double scale) async {
    final page = await _doc.getPage(pageIndex + 1);
    try {
      final rendered = await page.render(
        width: page.width * scale,
        height: page.height * scale,
        format: pdfx.PdfPageImageFormat.png,
      );
      if (rendered == null) {
        throw StateError('PDF page $pageIndex failed to render');
      }
      final codec = await ui.instantiateImageCodec(rendered.bytes);
      final frame = await codec.getNextFrame();
      return frame.image;
    } finally {
      await page.close();
    }
  }

  @override
  Future<void> close() => _doc.close();
}
