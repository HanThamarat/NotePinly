import 'dart:ui' as ui;

import '../../domain/entities/note_document.dart';
import '../../presentation/editor/canvas/ink_painters.dart';

/// Renders the first page of a document to PNG bytes for the library
/// grid, using the same ribbon geometry as the editor. Imported images
/// are omitted (decoding them here would double memory for marginal
/// preview value); ink and paper carry the recognizability.
Future<ui.Image?> renderThumbnailImage(NoteDocument doc,
    {double width = 360}) async {
  if (doc.pages.isEmpty) return null;
  final page = doc.pages.first;
  final cache = StrokePathCache();
  final picture = renderPageToPicture(
    spec: page.spec,
    strokes: page.strokes,
    cache: cache,
  );
  final scale = width / page.spec.width;
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder)
    ..scale(scale)
    ..drawPicture(picture);
  final scaled = recorder.endRecording();
  return scaled.toImage(width.round(), (page.spec.height * scale).round());
}

Future<List<int>?> renderThumbnailPng(NoteDocument doc,
    {double width = 360}) async {
  final image = await renderThumbnailImage(doc, width: width);
  if (image == null) return null;
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data?.buffer.asUint8List();
}
