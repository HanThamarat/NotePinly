import 'package:flutter/material.dart';

import '../../../app/theme/oklch.dart';
import '../../../app/theme/tokens.dart';

/// Custom inks picked this session, most recent first. Module scope on
/// purpose (same pattern as the library's collapsed-folder memory): the
/// picker is recreated with every popover, but a mixed ink should stay
/// one tap away for the rest of the session.
final List<Color> _sessionRecentInks = [];

const int _kMaxRecentInks = 6;

/// One pickable ink family: a name for semantics plus the OKLCH hue
/// and chroma the shade ladder is built on.
class _InkFamily {
  const _InkFamily(this.name, this.hue, this.chroma);

  final String name;
  final double hue;
  final double chroma;
}

const _families = <_InkFamily>[
  _InkFamily('Red', 25, 0.16),
  _InkFamily('Orange', 55, 0.15),
  _InkFamily('Ochre', 95, 0.13),
  _InkFamily('Forest', 145, 0.13),
  _InkFamily('Teal', 195, 0.11),
  _InkFamily('Blue', 245, 0.13),
  _InkFamily('Violet', 295, 0.14),
  _InkFamily('Berry', 345, 0.15),
  _InkFamily('Graphite', 220, 0.012),
];

/// Perceptually even lightness ladder. Capped at 0.70 so the lightest
/// shade of every family still reads as ink against white paper.
const _shadeL = <double>[0.32, 0.41, 0.50, 0.60, 0.70];

const _shadeNames = <String>['Darkest', 'Dark', 'Medium', 'Light', 'Lightest'];

Color _shadeOf(_InkFamily family, int shade) =>
    Oklch(_shadeL[shade], family.chroma, family.hue).toColor();

/// Minimal two-tap ink mixer: hue dots, an ink-tuned shade ladder, and a
/// live handwriting preview. Composed in OKLCH so every reachable color
/// is a legible handwriting ink — there is no way to mix a bad one.
/// Lives inside a popover; calls [onChanged] on every tap so toolbar
/// preview and selection recolor follow live.
class InkColorPicker extends StatefulWidget {
  const InkColorPicker({
    super.key,
    required this.initial,
    required this.onChanged,
  });

  final Color initial;
  final ValueChanged<Color> onChanged;

  @override
  State<InkColorPicker> createState() => _InkColorPickerState();
}

class _InkColorPickerState extends State<InkColorPicker> {
  // The popover outlives several widget.initial updates (live recolors
  // feed back into the seed), so the session-recents check needs the
  // color the popover opened with — captured eagerly in initState; a
  // lazy `late` would read the already-updated seed at dispose time.
  late final Color _openedWith;
  late Color _current;
  late int _familyIndex;
  late int _shadeIndex;

  @override
  void initState() {
    super.initState();
    _openedWith = widget.initial;
    _current = widget.initial;
    final lch = Oklch.fromColor(widget.initial);
    _familyIndex = _nearestFamily(lch);
    _shadeIndex = _nearestShade(lch.l);
  }

  @override
  void dispose() {
    if (_current != _openedWith && !InkColors.penInks.contains(_current)) {
      _sessionRecentInks
        ..remove(_current)
        ..insert(0, _current);
      if (_sessionRecentInks.length > _kMaxRecentInks) {
        _sessionRecentInks.removeRange(
            _kMaxRecentInks, _sessionRecentInks.length);
      }
    }
    super.dispose();
  }

  static int _nearestFamily(Oklch lch) {
    // Near-neutral inks snap to graphite regardless of stored hue.
    if (lch.c < 0.05) return _families.length - 1;
    var best = 0;
    var bestDistance = double.infinity;
    for (var i = 0; i < _families.length - 1; i++) {
      final raw = (lch.h - _families[i].hue).abs() % 360;
      final distance = raw > 180 ? 360 - raw : raw;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = i;
      }
    }
    return best;
  }

  static int _nearestShade(double l) {
    var best = 0;
    for (var i = 1; i < _shadeL.length; i++) {
      if ((l - _shadeL[i]).abs() < (l - _shadeL[best]).abs()) best = i;
    }
    return best;
  }

  void _commit(Color color) {
    setState(() => _current = color);
    widget.onChanged(color);
  }

  void _pickFamily(int index) {
    setState(() => _familyIndex = index);
    _commit(_shadeOf(_families[index], _shadeIndex));
  }

  void _pickShade(int index) {
    setState(() => _shadeIndex = index);
    _commit(_shadeOf(_families[_familyIndex], index));
  }

  void _pickRecent(Color color) {
    final lch = Oklch.fromColor(color);
    setState(() {
      _familyIndex = _nearestFamily(lch);
      _shadeIndex = _nearestShade(lch.l);
    });
    _commit(color);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final duration = reduceMotion ? Duration.zero : InkDurations.fast;
    final recents = _sessionRecentInks.where((c) => c != _current).toList();

    return Padding(
      padding: const EdgeInsets.all(InkSpace.lg),
      child: SizedBox(
        width: 270,
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .start,
          children: [
            _InkPreview(color: _current, duration: duration),
            const SizedBox(height: InkSpace.md),
            Row(
              children: [
                for (var i = 0; i < _families.length; i++)
                  _HueDot(
                    family: _families[i],
                    selected: i == _familyIndex,
                    duration: duration,
                    onTap: () => _pickFamily(i),
                  ),
              ],
            ),
            const SizedBox(height: InkSpace.xs),
            SizedBox(
              height: 48,
              child: Row(
                children: [
                  for (var i = 0; i < _shadeL.length; i++) ...[
                    if (i > 0) const SizedBox(width: 4),
                    Expanded(
                      child: _ShadeSegment(
                        color: _shadeOf(_families[_familyIndex], i),
                        label:
                            '${_shadeNames[i]} ${_families[_familyIndex].name.toLowerCase()}',
                        selected: i == _shadeIndex,
                        duration: duration,
                        onTap: () => _pickShade(i),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (recents.isNotEmpty) ...[
              const SizedBox(height: InkSpace.sm),
              Row(
                children: [
                  const Text(
                    'Recent',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: InkColors.inkMuted,
                    ),
                  ),
                  const SizedBox(width: InkSpace.sm),
                  for (final color in recents)
                    Semantics(
                      button: true,
                      label: 'Recent ink',
                      child: InkResponse(
                        onTap: () => _pickRecent(color),
                        radius: 16,
                        child: SizedBox(
                          width: 26,
                          height: 36,
                          child: Center(
                            child: Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: color,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// White paper strip with a handwriting squiggle drawn in the candidate
/// ink, so the color is judged the way it will be used — as a written
/// line, not a paint chip. Hex readout tucked in the corner.
class _InkPreview extends StatelessWidget {
  const _InkPreview({required this.color, required this.duration});

  final Color color;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: color),
      duration: duration,
      curve: Curves.easeOutQuart,
      builder: (context, animated, _) {
        final ink = animated ?? color;
        return Container(
          height: 52,
          decoration: BoxDecoration(
            color: InkColors.page,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: InkColors.divider),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(painter: _SquigglePainter(ink)),
              ),
              Positioned(
                right: 8,
                bottom: 5,
                child: Text(
                  '#${(ink.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: InkColors.inkMuted,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SquigglePainter extends CustomPainter {
  _SquigglePainter(this.ink);

  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    // Baseline rule, like lined paper.
    canvas.drawLine(
      Offset(10, h * 0.76),
      Offset(size.width - 10, h * 0.76),
      Paint()
        ..color = InkColors.divider
        ..strokeWidth = 1,
    );
    // Cursive arches ending in a tail — reads as handwriting at a glance.
    final pen = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 2.6;
    final path = Path()
      ..moveTo(18, h * 0.72)
      ..cubicTo(22, h * 0.30, 34, h * 0.26, 38, h * 0.54)
      ..cubicTo(41, h * 0.74, 49, h * 0.76, 53, h * 0.52)
      ..cubicTo(57, h * 0.28, 67, h * 0.24, 71, h * 0.52)
      ..cubicTo(74, h * 0.72, 82, h * 0.74, 87, h * 0.50)
      ..cubicTo(92, h * 0.26, 100, h * 0.24, 104, h * 0.50)
      ..cubicTo(107, h * 0.70, 114, h * 0.74, 124, h * 0.58)
      ..cubicTo(132, h * 0.45, 140, h * 0.52, 148, h * 0.60);
    canvas.drawPath(path, pen);
    canvas.drawCircle(Offset(158, h * 0.62), 1.8, Paint()..color = ink);
  }

  @override
  bool shouldRepaint(_SquigglePainter oldDelegate) => oldDelegate.ink != ink;
}

/// Hue family dot — the toolbar swatch affordance at popover scale:
/// selected grows a ring of its own color.
class _HueDot extends StatelessWidget {
  const _HueDot({
    required this.family,
    required this.selected,
    required this.duration,
    required this.onTap,
  });

  final _InkFamily family;
  final bool selected;
  final Duration duration;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _shadeOf(family, 2);
    return Semantics(
      button: true,
      selected: selected,
      label: '${family.name} ink',
      child: InkResponse(
        onTap: onTap,
        radius: 18,
        child: SizedBox(
          width: 30,
          height: 40,
          child: Center(
            child: AnimatedContainer(
              duration: duration,
              curve: Curves.easeOutQuart,
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? color : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Center(
                child: Container(
                  width: selected ? 10 : 14,
                  height: selected ? 10 : 14,
                  decoration:
                      BoxDecoration(shape: BoxShape.circle, color: color),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One step of the shade ladder. The selected step lifts: taller, white
/// hairline, soft shadow — visible against any ink without stealing hue.
class _ShadeSegment extends StatelessWidget {
  const _ShadeSegment({
    required this.color,
    required this.label,
    required this.selected,
    required this.duration,
    required this.onTap,
  });

  final Color color;
  final String label;
  final bool selected;
  final Duration duration;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: Center(
          child: AnimatedContainer(
            duration: duration,
            curve: Curves.easeOutQuart,
            height: selected ? 42 : 32,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(7),
              border: selected
                  ? Border.all(color: Colors.white, width: 2)
                  : null,
              boxShadow: selected
                  ? const [
                      BoxShadow(
                        color: Color(0x33253237),
                        blurRadius: 6,
                        offset: Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// The hue-ring swatch that opens the ink mixer in a popover. Shared by
/// the toolbar (seventh swatch) and the selection bar (custom recolor)
/// so the affordance reads identically everywhere.
class CustomColorButton extends StatelessWidget {
  const CustomColorButton({
    super.key,
    required this.currentColor,
    required this.isActive,
    required this.onColorSelected,
    this.label = 'Custom color',
    this.cellWidth = 32,
    this.cellHeight = 44,
  });

  final Color currentColor;

  /// Whether [currentColor] is a custom ink (ring shows it) rather than
  /// a preset (ring shows the rainbow).
  final bool isActive;
  final ValueChanged<Color> onColorSelected;
  final String label;
  final double cellWidth;
  final double cellHeight;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: [
        InkColorPicker(initial: currentColor, onChanged: onColorSelected),
      ],
      builder: (context, menuController, _) => Tooltip(
        message: label,
        child: Semantics(
          button: true,
          label: label,
          child: InkResponse(
            onTap: () => menuController.isOpen
                ? menuController.close()
                : menuController.open(),
            radius: 20,
            child: SizedBox(
              width: cellWidth,
              height: cellHeight,
              child: Center(
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isActive ? currentColor : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: Container(
                      width: isActive ? 12 : 16,
                      height: isActive ? 12 : 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: isActive
                            ? null
                            : const SweepGradient(colors: [
                                Color(0xFFB02A2D),
                                Color(0xFFD0750A),
                                Color(0xFF287C42),
                                Color(0xFF005D89),
                                Color(0xFF623E96),
                                Color(0xFFB02A2D),
                              ]),
                        color: isActive ? currentColor : null,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
