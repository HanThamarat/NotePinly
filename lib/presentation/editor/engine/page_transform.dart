import 'dart:math' as math;
import 'dart:ui';

import '../../../domain/entities/page_spec.dart';

/// Maps between page coordinates (where ink/images/PDF are stored,
/// pre-rotation) and display coordinates (what the camera and screen
/// see). Applying the same quarter-turn at render time is what makes all
/// content rotate together for free.
class PageTransform {
  const PageTransform(this.spec);

  final PageSpec spec;

  Size get displaySize => Size(spec.displayWidth, spec.displayHeight);

  /// Canvas transform: after this, drawing in page coordinates lands at
  /// the right display position.
  void applyTo(Canvas canvas) {
    switch (spec.rotation % 4) {
      case 1:
        canvas
          ..translate(spec.height, 0)
          ..rotate(math.pi / 2);
      case 2:
        canvas
          ..translate(spec.width, spec.height)
          ..rotate(math.pi);
      case 3:
        canvas
          ..translate(0, spec.width)
          ..rotate(3 * math.pi / 2);
    }
  }

  Offset displayToPage(Offset d) => switch (spec.rotation % 4) {
        1 => Offset(d.dy, spec.height - d.dx),
        2 => Offset(spec.width - d.dx, spec.height - d.dy),
        3 => Offset(spec.width - d.dy, d.dx),
        _ => d,
      };

  Offset pageToDisplay(Offset p) => switch (spec.rotation % 4) {
        1 => Offset(spec.height - p.dy, p.dx),
        2 => Offset(spec.width - p.dx, spec.height - p.dy),
        3 => Offset(p.dy, spec.width - p.dx),
        _ => p,
      };
}
