import 'dart:ui' as ui;

/// Abstraction over the PDF engine (pdfx in production, fakes in tests)
/// so the editor and repositories never depend on the plugin directly.
abstract interface class PdfRenderer {
  Future<PdfDocumentHandle> open(String path);
}

abstract interface class PdfDocumentHandle {
  int get pageCount;

  /// Page size in PDF points (1/72 inch).
  Future<ui.Size> pageSize(int pageIndex);

  /// Rasterizes one page at [scale] × its point size.
  Future<ui.Image> renderPage(int pageIndex, double scale);

  Future<void> close();
}
