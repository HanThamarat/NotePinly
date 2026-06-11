import 'package:flutter/material.dart';

import '../../../app/theme/tokens.dart';
import 'color_picker.dart';

/// Floating action bar shown while a lasso selection (or an image) is
/// active: recolor swatches + custom ink mixer, delete, dismiss. Quiet,
/// one row, no modal.
class SelectionBar extends StatelessWidget {
  const SelectionBar({
    super.key,
    required this.strokeCount,
    required this.isImage,
    required this.selectionColor,
    required this.onRecolor,
    required this.onDelete,
    required this.onDismiss,
  });

  final int strokeCount;
  final bool isImage;

  /// Current ink of the selection (first selected stroke); seeds the
  /// custom mixer so it opens on the shade being replaced.
  final Color selectionColor;
  final ValueChanged<Color> onRecolor;
  final VoidCallback onDelete;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 6,
      shadowColor: const Color(0x33253237),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: InkSpace.md, vertical: InkSpace.xs),
        child: Row(
          mainAxisSize: .min,
          children: [
            Text(
              isImage ? 'Image' : '$strokeCount selected',
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                color: InkColors.ink,
              ),
            ),
            if (!isImage) ...[
              const SizedBox(width: InkSpace.md),
              for (final color in InkColors.penInks)
                Semantics(
                  button: true,
                  label: 'Recolor selection',
                  child: InkResponse(
                    onTap: () => onRecolor(color),
                    radius: 18,
                    child: SizedBox(
                      width: 28,
                      height: 44,
                      child: Center(
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration:
                              BoxDecoration(shape: BoxShape.circle, color: color),
                        ),
                      ),
                    ),
                  ),
                ),
              CustomColorButton(
                currentColor: selectionColor,
                isActive: !InkColors.penInks.contains(selectionColor),
                onColorSelected: onRecolor,
                label: 'Custom recolor',
                cellWidth: 28,
              ),
            ],
            const SizedBox(width: InkSpace.sm),
            Container(width: 1, height: 22, color: InkColors.divider),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              tooltip: 'Delete selection',
              onPressed: onDelete,
              iconSize: 20,
              color: InkColors.ink,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded),
              tooltip: 'Deselect',
              onPressed: onDismiss,
              iconSize: 20,
              color: InkColors.inkMuted,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            ),
          ],
        ),
      ),
    );
  }
}
