import 'package:flutter/material.dart';

import '../../../app/theme/tokens.dart';

/// Bottom-center page navigator: previous / "2 of 5" / next / add page.
/// Hidden for whiteboards and single-page notes without neighbors.
class PageChip extends StatelessWidget {
  const PageChip({
    super.key,
    required this.pageIndex,
    required this.pageCount,
    required this.onPageChanged,
    required this.onAddPage,
  });

  final int pageIndex;
  final int pageCount;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onAddPage;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 4,
      shadowColor: const Color(0x26253237),
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: InkSpace.xs),
        child: Row(
          mainAxisSize: .min,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left_rounded),
              tooltip: 'Previous page',
              onPressed:
                  pageIndex > 0 ? () => onPageChanged(pageIndex - 1) : null,
              iconSize: 22,
              color: InkColors.ink,
              disabledColor: InkColors.inkDisabled,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            ),
            AnimatedSwitcher(
              duration: InkDurations.fast,
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(scale: animation, child: child),
              ),
              child: Text(
                '${pageIndex + 1} of $pageCount',
                key: ValueKey('$pageIndex/$pageCount'),
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: InkColors.ink,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right_rounded),
              tooltip: 'Next page',
              onPressed: pageIndex < pageCount - 1
                  ? () => onPageChanged(pageIndex + 1)
                  : null,
              iconSize: 22,
              color: InkColors.ink,
              disabledColor: InkColors.inkDisabled,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            ),
            Container(width: 1, height: 20, color: InkColors.divider),
            IconButton(
              icon: const Icon(Icons.add_rounded),
              tooltip: 'Add page',
              onPressed: onAddPage,
              iconSize: 22,
              color: InkColors.ink,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            ),
          ],
        ),
      ),
    );
  }
}
