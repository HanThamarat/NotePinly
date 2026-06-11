import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app/theme/tokens.dart';

/// Floating "New page" pill shown while the user keeps pulling up at the
/// end of the document. Driven by the canvas overscroll progress (0..1);
/// it fades and slides in as the pull charges.
class PageTurnHint extends StatelessWidget {
  const PageTurnHint({super.key, required this.progress});

  final ValueListenable<double> progress;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: progress,
      builder: (context, value, _) {
        if (value <= 0) return const SizedBox.shrink();
        final t = Curves.easeOut.transform(value.clamp(0.0, 1.0));
        return Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 72),
            child: Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, (1 - t) * 14),
                child: Material(
                  color: Colors.white,
                  elevation: 4,
                  shadowColor: const Color(0x26253237),
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: InkSpace.lg, vertical: InkSpace.sm),
                    child: Row(
                      mainAxisSize: .min,
                      children: const [
                        Icon(Icons.add_rounded,
                            size: 17, color: InkColors.inkMuted),
                        SizedBox(width: InkSpace.sm),
                        Text(
                          'New page', //fwfwaffwa
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                            color: InkColors.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
