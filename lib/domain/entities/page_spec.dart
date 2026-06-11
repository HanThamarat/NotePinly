import 'package:equatable/equatable.dart';

enum PaperTemplate { blank, lined, grid, dotted }

/// Geometry and background of one page. Width/height are pre-rotation
/// logical points; [rotation] is quarter-turns clockwise (0..3) applied
/// at render time so ink, images, and PDF background rotate together.
class PageSpec extends Equatable {
  const PageSpec({
    required this.id,
    this.width = 816,
    this.height = 1056,
    this.template = PaperTemplate.blank,
    this.rotation = 0,
    this.pdfPageIndex,
  });

  final String id;
  final double width;
  final double height;
  final PaperTemplate template;
  final int rotation;

  /// When set, the page background is this page of the note's source PDF.
  final int? pdfPageIndex;

  bool get isSideways => rotation.isOdd;
  double get displayWidth => isSideways ? height : width;
  double get displayHeight => isSideways ? width : height;

  PageSpec copyWith({PaperTemplate? template, int? rotation}) => PageSpec(
        id: id,
        width: width,
        height: height,
        template: template ?? this.template,
        rotation: rotation ?? this.rotation,
        pdfPageIndex: pdfPageIndex,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'w': width,
        'h': height,
        'template': template.name,
        'rotation': rotation,
        if (pdfPageIndex != null) 'pdfPage': pdfPageIndex,
      };

  factory PageSpec.fromJson(Map<String, dynamic> json) => PageSpec(
        id: json['id'] as String,
        width: (json['w'] as num).toDouble(),
        height: (json['h'] as num).toDouble(),
        template: PaperTemplate.values.byName(json['template'] as String),
        rotation: (json['rotation'] as num?)?.toInt() ?? 0,
        pdfPageIndex: (json['pdfPage'] as num?)?.toInt(),
      );

  @override
  List<Object?> get props => [id, width, height, template, rotation, pdfPageIndex];
}
