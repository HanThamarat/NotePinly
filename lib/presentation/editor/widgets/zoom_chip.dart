import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/theme/tokens.dart';

/// Transient zoom-level indicator shown while pinching, fading out after
/// a beat of inactivity. State feedback only — never blocks input.
class ZoomChip extends StatefulWidget {
  const ZoomChip({super.key, required this.scaleNotifier});

  /// Emits the camera scale whenever a pinch changes it.
  final ValueNotifier<double?> scaleNotifier;

  @override
  State<ZoomChip> createState() => _ZoomChipState();
}

class _ZoomChipState extends State<ZoomChip> {
  Timer? _fadeTimer;
  double? _scale;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    widget.scaleNotifier.addListener(_onScale);
  }

  @override
  void dispose() {
    widget.scaleNotifier.removeListener(_onScale);
    _fadeTimer?.cancel();
    super.dispose();
  }

  void _onScale() {
    final scale = widget.scaleNotifier.value;
    if (scale == null) return;
    _fadeTimer?.cancel();
    setState(() {
      _scale = scale;
      _visible = true;
    });
    _fadeTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _visible = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: reduceMotion ? Duration.zero : InkDurations.medium,
        curve: Curves.easeOutQuart,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: InkSpace.md,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: InkColors.ink.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '${((_scale ?? 1) * 100).round()}%',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: Colors.white,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }
}
