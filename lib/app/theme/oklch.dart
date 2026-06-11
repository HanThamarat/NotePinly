import 'dart:math';
import 'dart:ui';

/// OKLCH <-> sRGB conversion (Björn Ottosson's OKLab, D65).
///
/// The ink mixer composes shade ladders in OKLCH so every step is
/// perceptually even and every hue lands at the same visual weight —
/// a yellow and a blue at the same L genuinely look equally dark on
/// paper, which HSV cannot promise.
final class Oklch {
  const Oklch(this.l, this.c, this.h);

  /// Lightness 0..1, chroma 0..~0.37, hue in degrees.
  final double l;
  final double c;
  final double h;

  factory Oklch.fromColor(Color color) {
    final r = _srgbToLinear(color.r);
    final g = _srgbToLinear(color.g);
    final b = _srgbToLinear(color.b);

    final lms0 = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b;
    final lms1 = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b;
    final lms2 = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b;

    final l_ = _cbrt(lms0);
    final m_ = _cbrt(lms1);
    final s_ = _cbrt(lms2);

    final okL = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_;
    final okA = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_;
    final okB = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_;

    final chroma = sqrt(okA * okA + okB * okB);
    var hue = atan2(okB, okA) * 180 / pi;
    if (hue < 0) hue += 360;
    return Oklch(okL, chroma, hue);
  }

  /// Converts to sRGB, walking chroma toward neutral until the color
  /// fits the gamut. Hue and lightness are never sacrificed, so a
  /// ladder built on a fixed L stays a true ladder for every hue.
  Color toColor() {
    var lo = 0.0, hi = c;
    var rgb = _toLinearRgb(l, hi, h);
    if (_inGamut(rgb)) return _encode(rgb);
    for (var i = 0; i < 16; i++) {
      final mid = (lo + hi) / 2;
      rgb = _toLinearRgb(l, mid, h);
      if (_inGamut(rgb)) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return _encode(_toLinearRgb(l, lo, h));
  }

  static List<double> _toLinearRgb(double l, double c, double h) {
    final hRad = h * pi / 180;
    final a = c * cos(hRad);
    final b = c * sin(hRad);

    final l_ = l + 0.3963377774 * a + 0.2158037573 * b;
    final m_ = l - 0.1055613458 * a - 0.0638541728 * b;
    final s_ = l - 0.0894841775 * a - 1.2914855480 * b;

    final l3 = l_ * l_ * l_;
    final m3 = m_ * m_ * m_;
    final s3 = s_ * s_ * s_;

    return [
      4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3,
      -1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3,
      -0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3,
    ];
  }

  static bool _inGamut(List<double> rgb) =>
      rgb.every((v) => v >= -0.0001 && v <= 1.0001);

  static Color _encode(List<double> rgb) => Color.from(
        alpha: 1,
        red: _linearToSrgb(rgb[0].clamp(0.0, 1.0)),
        green: _linearToSrgb(rgb[1].clamp(0.0, 1.0)),
        blue: _linearToSrgb(rgb[2].clamp(0.0, 1.0)),
      );

  static double _srgbToLinear(double v) =>
      v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4).toDouble();

  static double _linearToSrgb(double v) =>
      v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055;

  static double _cbrt(double v) =>
      v < 0 ? -pow(-v, 1 / 3).toDouble() : pow(v, 1 / 3).toDouble();
}
