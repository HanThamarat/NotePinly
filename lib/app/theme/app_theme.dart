import 'package:flutter/material.dart';

import 'tokens.dart';

/// Light chrome theme. Product register: one family (platform default),
/// fixed type scale at a 1.125-1.2 ratio, quiet neutrals, the brand
/// steel-blue reserved for active/selected/focus marks.
ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: .fromSeed(
      seedColor: InkColors.primary,
      surface: InkColors.chrome,
      onSurface: InkColors.ink,
    ),
  );

  return base.copyWith(
    scaffoldBackgroundColor: InkColors.backdrop,
    splashFactory: InkSparkle.splashFactory,
    dividerTheme: const DividerThemeData(
      color: InkColors.divider,
      thickness: 1,
      space: 1,
    ),
    iconTheme: const IconThemeData(color: InkColors.ink, size: 22),
    textTheme: base.textTheme.copyWith(
      // Note title in the toolbar.
      titleMedium: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: InkColors.ink,
        letterSpacing: 0.1,
      ),
      // Secondary chrome text (zoom chip, tooltips body).
      bodySmall: const TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w400,
        color: InkColors.inkMuted,
      ),
      // Buttons inherit this; keep all type inside the text theme so the
      // platform family resolves consistently.
      labelLarge: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.1,
      ),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 500),
      decoration: BoxDecoration(
        color: InkColors.ink,
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: const TextStyle(fontSize: 12.5, color: Colors.white),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(Colors.white),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(8),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: InkColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
  );
}
