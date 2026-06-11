import 'package:equatable/equatable.dart';

import 'image_object.dart';
import 'page_spec.dart';
import 'stroke.dart';

enum NoteKind { note, whiteboard }

/// Whiteboards use one huge page; "effectively infinite" for hand use.
const whiteboardExtent = 20000.0;

class NotePage extends Equatable {
  const NotePage({
    required this.spec,
    this.strokes = const [],
    this.images = const [],
  });

  final PageSpec spec;
  final List<Stroke> strokes;
  final List<ImageObject> images;

  NotePage copyWith({
    PageSpec? spec,
    List<Stroke>? strokes,
    List<ImageObject>? images,
  }) =>
      NotePage(
        spec: spec ?? this.spec,
        strokes: strokes ?? this.strokes,
        images: images ?? this.images,
      );

  Map<String, dynamic> toJson() => {
        'spec': spec.toJson(),
        'strokes': [for (final s in strokes) s.toJson()],
        'images': [for (final i in images) i.toJson()],
      };

  factory NotePage.fromJson(Map<String, dynamic> json) => NotePage(
        spec: PageSpec.fromJson(json['spec'] as Map<String, dynamic>),
        strokes: [
          for (final s in json['strokes'] as List)
            Stroke.fromJson(s as Map<String, dynamic>),
        ],
        images: [
          for (final i in (json['images'] as List? ?? const []))
            ImageObject.fromJson(i as Map<String, dynamic>),
        ],
      );

  @override
  List<Object?> get props => [spec, strokes, images];
}

/// The canonical note content — what content.json holds.
class NoteDocument extends Equatable {
  const NoteDocument({
    required this.id,
    this.kind = NoteKind.note,
    required this.pages,
    this.sourcePdfPath,
  });

  final String id;
  final NoteKind kind;
  final List<NotePage> pages;

  /// Original PDF file (inside the note directory) for PDF-backed notes.
  final String? sourcePdfPath;

  factory NoteDocument.blank({
    required String id,
    NoteKind kind = NoteKind.note,
    PaperTemplate template = PaperTemplate.blank,
  }) =>
      NoteDocument(
        id: id,
        kind: kind,
        pages: [
          NotePage(
            spec: kind == NoteKind.whiteboard
                ? PageSpec(
                    id: '$id-p0',
                    width: whiteboardExtent,
                    height: whiteboardExtent,
                  )
                : PageSpec(id: '$id-p0', template: template),
          ),
        ],
      );

  NoteDocument withPage(int index, NotePage page) {
    final next = [...pages];
    next[index] = page;
    return NoteDocument(
      id: id,
      kind: kind,
      pages: next,
      sourcePdfPath: sourcePdfPath,
    );
  }

  NoteDocument insertPage(int index, NotePage page) => NoteDocument(
        id: id,
        kind: kind,
        pages: [...pages.take(index), page, ...pages.skip(index)],
        sourcePdfPath: sourcePdfPath,
      );

  NoteDocument removePageAt(int index) => NoteDocument(
        id: id,
        kind: kind,
        pages: [...pages.take(index), ...pages.skip(index + 1)],
        sourcePdfPath: sourcePdfPath,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        if (sourcePdfPath != null) 'sourcePdf': sourcePdfPath,
        'pages': [for (final p in pages) p.toJson()],
      };

  factory NoteDocument.fromJson(Map<String, dynamic> json) => NoteDocument(
        id: json['id'] as String,
        kind: NoteKind.values.byName(json['kind'] as String? ?? 'note'),
        sourcePdfPath: json['sourcePdf'] as String?,
        pages: [
          for (final p in json['pages'] as List)
            NotePage.fromJson(p as Map<String, dynamic>),
        ],
      );

  @override
  List<Object?> get props => [id, kind, pages, sourcePdfPath];
}
