import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app/theme/tokens.dart';

/// Floating pill that previews a scroll page-turn: "Next page",
/// "New page" (past the last page) or "Previous page". Driven by the
/// canvas overscroll progress (-1..1, positive = forward); it fades and
/// slides in as the user keeps pulling.
class PageTurnHint extends StatelessWidget {
  const PageTurnHint({
    super.key,
    required this.progress,
    required this.hasNextPage,
    required this.hasPreviousPage,
  });

  final ValueListenable<double> progress;
  final bool hasNextPage;
  final bool hasPreviousPage;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: progress,
      builder: (context, value, _) {
        if (value == 0) return const SizedBox.shrink();
        final forward = value > 0;
        if (!forward && !hasPreviousPage) return const SizedBox.shrink();
        final t = Curves.easeOut.transform(value.abs().clamp(0.0, 1.0));
        final label = forward
            ? (hasNextPage ? 'Next page' : 'New page')
            : 'Previous page';
        final icon = forward
            ? (hasNextPage
                ? Icons.arrow_downward_rounded
                : Icons.add_rounded)
            : Icons.arrow_upward_rounded;
        return Align(
          alignment: forward ? Alignment.bottomCenter : Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 72),
            child: Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, (1 - t) * 14 * (forward ? 1 : -1)),
                child: Material(
                  color: t >= 1 ? InkColors.primary : Colors.white,
                  elevation: 4,
                  shadowColor: const Color(0x26253237),
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: InkSpace.lg, vertical: InkSpace.sm),
                    child: Row(
                      mainAxisSize: .min,
                      children: [
                        Icon(icon,
                            size: 17,
                            color:
                                t >= 1 ? Colors.white : InkColors.inkMuted),
                        const SizedBox(width: InkSpace.sm),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                            color: t >= 1 ? Colors.white : InkColors.ink,
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
