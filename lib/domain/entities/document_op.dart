import 'dart:ui' show Color, Offset;

import 'image_object.dart';
import 'note_document.dart';
import 'page_spec.dart';
import 'stroke.dart';

/// One undoable, journalable change to a [NoteDocument].
///
/// Ops are the single source of mutation: the undo/redo stacks hold them,
/// and the crash-recovery journal serializes them line by line. Every op
/// must apply and invert purely, and round-trip through JSON.
sealed class DocumentOp {
  const DocumentOp();

  NoteDocument apply(NoteDocument doc);
  NoteDocument invert(NoteDocument doc);
  Map<String, dynamic> toJson();

  static DocumentOp fromJson(Map<String, dynamic> json) {
    return switch (json['op'] as String) {
      'addStroke' => AddStrokeOp.fromJson(json),
      'eraseStrokes' => EraseStrokesOp.fromJson(json),
      'replaceStrokes' => ReplaceStrokesOp.fromJson(json),
      'recolorStrokes' => RecolorStrokesOp.fromJson(json),
      'addImage' => AddImageOp.fromJson(json),
      'transformImage' => TransformImageOp.fromJson(json),
      'deleteImage' => DeleteImageOp.fromJson(json),
      'addPage' => AddPageOp.fromJson(json),
      'setTemplate' => SetTemplateOp.fromJson(json),
      'rotatePage' => RotatePageOp.fromJson(json),
      'clearPage' => ClearPageOp.fromJson(json),
      final other => throw FormatException('Unknown op "$other"'),
    };
  }
}

NotePage _page(NoteDocument doc, int index) => doc.pages[index];

List<Stroke> _without(List<Stroke> strokes, Iterable<String> ids) {
  final gone = ids.toSet();
  return [for (final s in strokes) if (!gone.contains(s.id)) s];
}

final class AddStrokeOp extends DocumentOp {
  const AddStrokeOp(this.pageIndex, this.stroke);

  final int pageIndex;
  final Stroke stroke;

  @override
  NoteDocument apply(NoteDocument doc) {
    final page = _page(doc, pageIndex);
    // Idempotent: journal replay after a crash mid-snapshot may re-apply.
    if (page.strokes.any((s) => s.id == stroke.id)) return doc;
    return doc.withPage(
      pageIndex,
      page.copyWith(strokes: [...page.strokes, stroke]),
    );
  }

  @override
  NoteDocument invert(NoteDocument doc) {
    final page = _page(doc, pageIndex);
    return doc.withPage(
      pageIndex,
      page.copyWith(strokes: _without(page.strokes, [stroke.id])),
    );
  }

  @override
  Map<String, dynamic> toJson() =>
      {'op': 'addStroke', 'page': pageIndex, 'stroke': stroke.toJson()};

  factory AddStrokeOp.fromJson(Map<String, dynamic> json) => AddStrokeOp(
        (json['page'] as num).toInt(),
        Stroke.fromJson(json['stroke'] as Map<String, dynamic>),
      );
}

/// Erase: removes whole strokes and (for the partial eraser) appends the
/// surviving fragments. One op per eraser drag.
final class EraseStrokesOp extends DocumentOp {
  const EraseStrokesOp(this.pageIndex, this.removed, this.added);

  final int pageIndex;
  final List<Stroke> removed;
  final List<Stroke> added;

  @override
  NoteDocument apply(NoteDocument doc) {
    final page = _page(doc, pageIndex);
    final existing = {for (final s in page.strokes) s.id};
    return doc.withPage(
      pageIndex,
      page.copyWith(strokes: [
        ..._without(page.strokes, removed.map((s) => s.id)),
        // Skip fragments that already exist (idempotent journal replay).
        ...added.where((s) =>
            !existing.contains(s.id) || removed.any((r) => r.id == s.id)),
      ]),
    );
  }

  @override
  NoteDocument invert(NoteDocument doc) {
    final page = _page(doc, pageIndex);
    return doc.withPage(
      pageIndex,
      page.copyWith(strokes: [
        ..._without(page.strokes, added.map((s) => s.id)),
        ...removed,
      ]),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'op': 'eraseStrokes',
        'page': pageIndex,
        'removed': [for (final s in removed) s.toJson()],
        'added': [for (final s in added) s.toJson()],
      };

  factory EraseStrokesOp.fromJson(Map<String, dynamic> json) => EraseStrokesOp(
        (json['page'] as num).toInt(),
        [
          for (final s in json['removed'] as List)
            Stroke.fromJson(s as Map<String, dynamic>)
        ],
        [
          for (final s in json['added'] as List)
            Stroke.fromJson(s as Map<String, dynamic>)
        ],
      );
}

/// Generic stroke replacement — covers lasso move/resize (and deletion
/// when [after] is empty). Before/after must pair by stroke id.
final class ReplaceStrokesOp extends DocumentOp {
  const ReplaceStrokesOp(this.pageIndex, this.before, this.after);

  final int pageIndex;
  final List<Stroke> before;
  final List<Stroke> after;

  @override
  NoteDocument apply(NoteDocument doc) {
    final page = _page(doc, pageIndex);
    return doc.withPage(
      pageIndex,
      page.copyWith(strokes: [
        ..._without(page.strokes, before.map((s) => s.id)),
        ...after,
      ]),
    );
  }

  @override
  NoteDocument invert(NoteDocument doc) {
    final page = _page(doc, pageIndex);
    return doc.withPage(
      pageIndex,
      page.copyWith(strokes: [
        ..._without(page.strokes, after.map((s) => s.id)),
        ...before,
      ]),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'op': 'replaceStrokes',
        'page': pageIndex,
        'before': [for (final s in before) s.toJson()],
        'after': [for (final s in after) s.toJson()],
      };

  factory ReplaceStrokesOp.fromJson(Map<String, dynamic> json) =>
      ReplaceStrokesOp(
        (json['page'] as num).toInt(),
        [
          for (final s in json['before'] as List)
            Stroke.fromJson(s as Map<String, dynamic>)
        ],
        [
          for (final s in json['after'] as List)
            Stroke.fromJson(s as Map<String, dynamic>)
        ],
      );
}

final class RecolorStrokesOp extends DocumentOp {
  const RecolorStrokesOp(this.pageIndex, this.strokeIds, this.oldColors,
      this.newColor);

  final int pageIndex;
  final List<String> strokeIds;

  /// Parallel to [strokeIds]: each stroke's color before the recolor.
  final List<int> oldColors;
  final int newColor;

  @override
  NoteDocument apply(NoteDocument doc) => _recolor(
        doc,
        {for (final id in strokeIds) id: newColor},
      );

  @override
  NoteDocument invert(NoteDocument doc) => _recolor(doc, {
        for (var i = 0; i < strokeIds.length; i++) strokeIds[i]: oldColors[i],
      });

  NoteDocument _recolor(NoteDocument doc, Map<String, int> colorById) {
    final page = _page(doc, pageIndex);
    return doc.withPage(
      pageIndex,
      page.copyWith(strokes: [
        for (final s in page.strokes)
          colorById.containsKey(s.id)
              ? s.copyWith(color: Color(colorById[s.id]!))
              : s,
      ]),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'op': 'recolorStrokes',
        'page': pageIndex,
        'ids': strokeIds,
        'oldColors': oldColors,
        'newColor': newColor,
      };

  factory RecolorStrokesOp.fromJson(Map<String, dynamic> json) =>
      RecolorStrokesOp(
        (json['page'] as num).toInt(),
        [for (final id in json['ids'] as List) id as String],
        [for (final c in json['oldColors'] as List) (c as num).toInt()],
        (json['newColor'] as num).toInt(),
      );
}

final class AddImageOp extends DocumentOp {
  const AddImageOp(this.pageIndex, this.image);

  final int pageIndex;
  final ImageObject image;

  @override
  NoteDocument apply(NoteDocument doc) {
    final page = _page(doc, pageIndex);
    if (page.images.any((i) => i.id == image.id)) return doc;
    return doc.withPage(
        pageIndex, page.copyWith(images: [...page.images, image]));
  }

  @override
  NoteDocument invert(NoteDocument doc) {
    final page = _page(doc, pageIndex);
    return doc.withPage(
      pageIndex,
      page.copyWith(
          images: [for (final i in page.images) if (i.id != image.id) i]),
    );
  }

  @override
  Map<String, dynamic> toJson() =>
      {'op': 'addImage', 'page': pageIndex, 'image': image.toJson()};

  factory AddImageOp.fromJson(Map<String, dynamic> json) => AddImageOp(
        (json['page'] as num).toInt(),
        ImageObject.fromJson(json['image'] as Map<String, dynamic>),
      );
}

final class TransformImageOp extends DocumentOp {
  const TransformImageOp(this.pageIndex, this.before, this.after);

  final int pageIndex;
  final ImageObject before;
  final ImageObject after;

  @override
  NoteDocument apply(NoteDocument doc) => _swap(doc, after);

  @override
  NoteDocument invert(NoteDocument doc) => _swap(doc, before);

  NoteDocument _swap(NoteDocument doc, ImageObject target) {
    final page = _page(doc, pageIndex);
    return doc.withPage(
      pageIndex,
      page.copyWith(
          images: [for (final i in page.images) i.id == target.id ? target : i]),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'op': 'transformImage',
        'page': pageIndex,
        'before': before.toJson(),
        'after': after.toJson(),
      };

  factory TransformImageOp.fromJson(Map<String, dynamic> json) =>
      TransformImageOp(
        (json['page'] as num).toInt(),
        ImageObject.fromJson(json['before'] as Map<String, dynamic>),
        ImageObject.fromJson(json['after'] as Map<String, dynamic>),
      );
}

final class DeleteImageOp extends DocumentOp {
  const DeleteImageOp(this.pageIndex, this.image, this.atIndex);

  final int pageIndex;
  final ImageObject image;
  final int atIndex;

  @override
  NoteDocument apply(NoteDocument doc) {
    final page = _page(doc, pageIndex);
    return doc.withPage(
      pageIndex,
      page.copyWith(
          images: [for (final i in page.images) if (i.id != image.id) i]),
    );
  }

  @override
  NoteDocument invert(NoteDocument doc) {
    final page = _page(doc, pageIndex);
    final images = [...page.images];
    images.insert(atIndex.clamp(0, images.length), image);
    return doc.withPage(pageIndex, page.copyWith(images: images));
  }

  @override
  Map<String, dynamic> toJson() => {
        'op': 'deleteImage',
        'page': pageIndex,
        'image': image.toJson(),
        'index': atIndex,
      };

  factory DeleteImageOp.fromJson(Map<String, dynamic> json) => DeleteImageOp(
        (json['page'] as num).toInt(),
        ImageObject.fromJson(json['image'] as Map<String, dynamic>),
        (json['index'] as num).toInt(),
      );
}

final class AddPageOp extends DocumentOp {
  const AddPageOp(this.atIndex, this.spec);

  final int atIndex;
  final PageSpec spec;

  @override
  NoteDocument apply(NoteDocument doc) {
    if (doc.pages.any((p) => p.spec.id == spec.id)) return doc;
    return doc.insertPage(atIndex, NotePage(spec: spec));
  }

  @override
  NoteDocument invert(NoteDocument doc) => doc.removePageAt(atIndex);

  @override
  Map<String, dynamic> toJson() =>
      {'op': 'addPage', 'index': atIndex, 'spec': spec.toJson()};

  factory AddPageOp.fromJson(Map<String, dynamic> json) => AddPageOp(
        (json['index'] as num).toInt(),
        PageSpec.fromJson(json['spec'] as Map<String, dynamic>),
      );
}

final class SetTemplateOp extends DocumentOp {
  const SetTemplateOp(this.pageIndex, this.oldTemplate, this.newTemplate);

  final int pageIndex;
  final PaperTemplate oldTemplate;
  final PaperTemplate newTemplate;

  @override
  NoteDocument apply(NoteDocument doc) => _set(doc, newTemplate);

  @override
  NoteDocument invert(NoteDocument doc) => _set(doc, oldTemplate);

  NoteDocument _set(NoteDocument doc, PaperTemplate t) {
    final page = _page(doc, pageIndex);
    return doc.withPage(pageIndex, page.copyWith(spec: page.spec.copyWith(template: t)));
  }

  @override
  Map<String, dynamic> toJson() => {
        'op': 'setTemplate',
        'page': pageIndex,
        'old': oldTemplate.name,
        'new': newTemplate.name,
      };

  factory SetTemplateOp.fromJson(Map<String, dynamic> json) => SetTemplateOp(
        (json['page'] as num).toInt(),
        PaperTemplate.values.byName(json['old'] as String),
        PaperTemplate.values.byName(json['new'] as String),
      );
}

/// Rotates the page one quarter-turn clockwise (or back on invert).
final class RotatePageOp extends DocumentOp {
  const RotatePageOp(this.pageIndex);

  final int pageIndex;

  @override
  NoteDocument apply(NoteDocument doc) => _turn(doc, 1);

  @override
  NoteDocument invert(NoteDocument doc) => _turn(doc, 3);

  NoteDocument _turn(NoteDocument doc, int quarters) {
    final page = _page(doc, pageIndex);
    return doc.withPage(
      pageIndex,
      page.copyWith(
        spec: page.spec.copyWith(
          rotation: (page.spec.rotation + quarters) % 4,
        ),
      ),
    );
  }

  @override
  Map<String, dynamic> toJson() => {'op': 'rotatePage', 'page': pageIndex};

  factory RotatePageOp.fromJson(Map<String, dynamic> json) =>
      RotatePageOp((json['page'] as num).toInt());
}

final class ClearPageOp extends DocumentOp {
  const ClearPageOp(this.pageIndex, this.strokes, this.images);

  final int pageIndex;
  final List<Stroke> strokes;
  final List<ImageObject> images;

  @override
  NoteDocument apply(NoteDocument doc) {
    final page = _page(doc, pageIndex);
    return doc.withPage(
        pageIndex, page.copyWith(strokes: const [], images: const []));
  }

  @override
  NoteDocument invert(NoteDocument doc) {
    final page = _page(doc, pageIndex);
    return doc.withPage(
      pageIndex,
      page.copyWith(
        strokes: [...page.strokes, ...strokes],
        images: [...page.images, ...images],
      ),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'op': 'clearPage',
        'page': pageIndex,
        'strokes': [for (final s in strokes) s.toJson()],
        'images': [for (final i in images) i.toJson()],
      };

  factory ClearPageOp.fromJson(Map<String, dynamic> json) => ClearPageOp(
        (json['page'] as num).toInt(),
        [
          for (final s in json['strokes'] as List)
            Stroke.fromJson(s as Map<String, dynamic>)
        ],
        [
          for (final i in (json['images'] as List? ?? const []))
            ImageObject.fromJson(i as Map<String, dynamic>)
        ],
      );
}

/// Moves/scales stroke geometry — used by lasso transforms.
Stroke transformStroke(Stroke stroke, {Offset offset = Offset.zero, double scale = 1, Offset pivot = Offset.zero}) {
  return Stroke(
    id: stroke.id,
    tool: stroke.tool,
    color: stroke.color,
    baseWidth: stroke.baseWidth * scale,
    points: [
      for (final p in stroke.points)
        StrokePoint(
          x: (p.x - pivot.dx) * scale + pivot.dx + offset.dx,
          y: (p.y - pivot.dy) * scale + pivot.dy + offset.dy,
          pressure: p.pressure,
          tilt: p.tilt,
          timestampMs: p.timestampMs,
        ),
    ],
  );
}
