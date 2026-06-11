import 'package:flutter/material.dart';

import '../../../app/theme/tokens.dart';

/// Compact custom color picker: saturation/value field + hue slider.
/// Lives inside a popover; calls [onChanged] live so the ink preview in
/// the toolbar follows the drag.
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
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);

  void _update(HSVColor next) {
    setState(() => _hsv = next);
    widget.onChanged(next.toColor());
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(InkSpace.md),
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .start,
        children: [
          // Saturation / value field.
          GestureDetector(
            onPanDown: (d) => _pickSV(d.localPosition),
            onPanUpdate: (d) => _pickSV(d.localPosition),
            child: CustomPaint(
              size: const Size(216, 140),
              painter: _SVFieldPainter(_hsv),
            ),
          ),
          const SizedBox(height: InkSpace.md),
          // Hue slider.
          GestureDetector(
            onPanDown: (d) => _pickHue(d.localPosition.dx),
            onPanUpdate: (d) => _pickHue(d.localPosition.dx),
            child: CustomPaint(
              size: const Size(216, 20),
              painter: _HueBarPainter(_hsv.hue),
            ),
          ),
          const SizedBox(height: InkSpace.md),
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _hsv.toColor(),
                  border: Border.all(color: InkColors.divider),
                ),
              ),
              const SizedBox(width: InkSpace.sm),
              Text(
                '#${(_hsv.toColor().toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}',
                style: const TextStyle(
                  fontSize: 13,
                  color: InkColors.inkMuted,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _pickSV(Offset p) {
    _update(_hsv
        .withSaturation((p.dx / 216).clamp(0.0, 1.0))
        .withValue(1 - (p.dy / 140).clamp(0.0, 1.0)));
  }

  void _pickHue(double x) {
    _update(_hsv.withHue((x / 216).clamp(0.0, 1.0) * 360));
  }
}

class _SVFieldPainter extends CustomPainter {
  _SVFieldPainter(this.hsv);

  final HSVColor hsv;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(8));
    canvas.clipRRect(rrect);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(colors: [
          Colors.white,
          HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor(),
        ]).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: .topCenter,
          end: .bottomCenter,
          colors: [Colors.transparent, Colors.black],
        ).createShader(rect),
    );
    final knob = Offset(hsv.saturation * size.width, (1 - hsv.value) * size.height);
    canvas.drawCircle(knob, 8, Paint()..color = Colors.white);
    canvas.drawCircle(
      knob,
      8,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = InkColors.ink,
    );
    canvas.drawCircle(knob, 5, Paint()..color = hsv.toColor());
  }

  @override
  bool shouldRepaint(_SVFieldPainter oldDelegate) => oldDelegate.hsv != hsv;
}

class _HueBarPainter extends CustomPainter {
  _HueBarPainter(this.hue);

  final double hue;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(10));
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = LinearGradient(colors: [
          for (var h = 0; h <= 360; h += 60)
            HSVColor.fromAHSV(1, h.toDouble() % 360, 1, 1).toColor(),
        ]).createShader(rect),
    );
    final x = hue / 360 * size.width;
    canvas.drawCircle(Offset(x, size.height / 2), 9, Paint()..color = Colors.white);
    canvas.drawCircle(
      Offset(x, size.height / 2),
      9,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = InkColors.ink,
    );
    canvas.drawCircle(Offset(x, size.height / 2), 6,
        Paint()..color = HSVColor.fromAHSV(1, hue, 1, 1).toColor());
  }

  @override
  bool shouldRepaint(_HueBarPainter oldDelegate) => oldDelegate.hue != hue;
}
