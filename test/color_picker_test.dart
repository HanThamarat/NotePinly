import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notepinly/app/theme/oklch.dart';
import 'package:notepinly/app/theme/tokens.dart';
import 'package:notepinly/presentation/editor/widgets/color_picker.dart';

void main() {
  group('Oklch', () {
    test('round-trips sRGB colors', () {
      for (final color in InkColors.penInks) {
        final back = Oklch.fromColor(color).toColor();
        expect((back.r - color.r).abs(), lessThan(0.01));
        expect((back.g - color.g).abs(), lessThan(0.01));
        expect((back.b - color.b).abs(), lessThan(0.01));
      }
    });

    test('out-of-gamut chroma clamps instead of clipping channels', () {
      final color = const Oklch(0.70, 0.30, 195).toColor();
      final lch = Oklch.fromColor(color);
      // Lightness survives; chroma walked into gamut.
      expect((lch.l - 0.70).abs(), lessThan(0.02));
      expect(lch.c, lessThan(0.30));
    });
  });

  group('InkColorPicker', () {
    /// Hosts the button the way the toolbar does: every pick feeds back
    /// into the seed, so `widget.initial` updates while the popover is
    /// open. The session-recents check must compare against the color
    /// the popover *opened* with, not the live seed.
    Widget host() => MaterialApp(
          home: Scaffold(
            body: Center(
              child: StatefulBuilder(
                builder: (context, setState) => _Harness(),
              ),
            ),
          ),
        );

    testWidgets('records the settled ink in recents despite a live seed',
        (tester) async {
      await tester.pumpWidget(host());

      await tester.tap(find.bySemanticsLabel('Custom color'));
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Teal ink'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Darkest teal'));
      await tester.pumpAndSettle();

      // Close (disposes the picker) and reopen.
      await tester.tap(find.bySemanticsLabel('Custom color'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Teal ink'), findsNothing);
      await tester.tap(find.bySemanticsLabel('Custom color'));
      await tester.pumpAndSettle();

      // The reopened picker seeds on the teal pick, so the recent dot
      // appears once the candidate moves elsewhere.
      await tester.tap(find.bySemanticsLabel('Berry ink'));
      await tester.pumpAndSettle();
      expect(find.text('Recent'), findsOneWidget);
      expect(find.bySemanticsLabel('Recent ink'), findsWidgets);
    });

    testWidgets('two taps mix an ink and report it live', (tester) async {
      await tester.pumpWidget(host());
      final state = tester.state<_HarnessState>(find.byType(_Harness));

      await tester.tap(find.bySemanticsLabel('Custom color'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Blue ink'));
      await tester.pumpAndSettle();
      final afterHue = state.color;
      expect(afterHue, isNot(Colors.black));

      await tester.tap(find.bySemanticsLabel('Lightest blue'));
      await tester.pumpAndSettle();
      final afterShade = state.color;
      expect(afterShade, isNot(afterHue));
      // Lighter shade really is lighter, and still ink (L capped at 0.70).
      final lch = Oklch.fromColor(afterShade);
      expect(lch.l, greaterThan(Oklch.fromColor(afterHue).l));
      expect(lch.l, lessThan(0.73));
    });
  });
}

class _Harness extends StatefulWidget {
  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  Color color = Colors.black;

  @override
  Widget build(BuildContext context) {
    return CustomColorButton(
      currentColor: color,
      isActive: !InkColors.penInks.contains(color),
      onColorSelected: (next) => setState(() => color = next),
    );
  }
}
