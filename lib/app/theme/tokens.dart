import 'dart:ui';

/// Design tokens for notepinly.
///
/// Palette composed in OKLCH around the brand seed oklch(0.55 0.09 210)
/// ("steel-blue chronometer") and converted to sRGB. The page itself is
/// literal white; the brand color appears only as an instrument mark on
/// active tool, selection, and focus states. Chrome neutrals carry a
/// 0.004-0.008 chroma tint toward the brand hue.
abstract final class InkColors {
  // Brand — oklch(0.55 0.09 210)
  static const primary = Color(0xFF177F8E);
  // oklch(0.50 0.09 210)
  static const primaryPressed = Color(0xFF00717F);
  // oklch(0.95 0.018 210) — active-tool pill fill
  static const primaryTint = Color(0xFFE2F2F5);

  // Surfaces
  static const page = Color(0xFFFFFFFF);
  // oklch(0.975 0.004 210) — toolbar
  static const chrome = Color(0xFFF4F7F8);
  // oklch(0.93 0.006 210) — desk behind the page
  static const backdrop = Color(0xFFE4E9EA);

  // Text & lines
  // oklch(0.25 0.015 220) — 13.9:1 on chrome
  static const ink = Color(0xFF1A2327);
  // oklch(0.50 0.015 220) — 5.4:1 on chrome
  static const inkMuted = Color(0xFF5A6569);
  // oklch(0.88 0.006 210)
  static const divider = Color(0xFFD3D9DA);
  // oklch(0.72 0.008 220) — disabled icons, 2.5:1 (non-interactive)
  static const inkDisabled = Color(0xFF9FA6A8);

  /// Pen ink palette — content colors, not UI chrome.
  /// Hand-tuned to read as ink on paper: dark enough to write with,
  /// saturated enough to tell apart at handwriting weight.
  static const penInks = <Color>[
    Color(0xFF161C1E), // ink black  oklch(0.22 0.01 220)
    Color(0xFF005D89), // fountain blue oklch(0.45 0.11 235)
    Color(0xFFB02A2D), // red oklch(0.50 0.17 25)
    Color(0xFF287C42), // green oklch(0.52 0.12 150)
    Color(0xFFD0750A), // orange oklch(0.65 0.15 60)
    Color(0xFF623E96), // violet oklch(0.45 0.14 300)
  ];
}

/// 4pt spacing scale.
abstract final class InkSpace {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

abstract final class InkDurations {
  /// Tool state changes, popovers. Never applied to the drawing path.
  static const fast = Duration(milliseconds: 160);
  static const medium = Duration(milliseconds: 220);
}
