import 'dart:ui' show Rect;

import 'package:equatable/equatable.dart';

/// An imported image placed on a page. [assetPath] points to the copied
/// file under the note's assets directory; geometry is in page-local
/// coordinates. Z-order is the position in the page's image list; ink
/// always renders above images.
class ImageObject extends Equatable {
  const ImageObject({
    required this.id,
    required this.assetPath,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final String id;
  final String assetPath;
  final double x;
  final double y;
  final double width;
  final double height;

  Rect get rect => Rect.fromLTWH(x, y, width, height);

  ImageObject withRect(Rect r) => ImageObject(
        id: id,
        assetPath: assetPath,
        x: r.left,
        y: r.top,
        width: r.width,
        height: r.height,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'asset': assetPath,
        'x': x,
        'y': y,
        'w': width,
        'h': height,
      };

  factory ImageObject.fromJson(Map<String, dynamic> json) => ImageObject(
        id: json['id'] as String,
        assetPath: json['asset'] as String,
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        width: (json['w'] as num).toDouble(),
        height: (json['h'] as num).toDouble(),
      );

  @override
  List<Object?> get props => [id, assetPath, x, y, width, height];
}
