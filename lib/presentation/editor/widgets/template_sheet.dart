import 'package:flutter/material.dart';

import '../../../app/theme/tokens.dart';
import '../../../domain/entities/page_spec.dart';

/// Bottom sheet for picking the current page's paper template. Each
/// option is a miniature painted page, not a labeled radio button — you
/// pick the paper you can see.
Future<PaperTemplate?> showTemplateSheet(
  BuildContext context, {
  required PaperTemplate current,
}) {
  return showModalBottomSheet<PaperTemplate>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(InkSpace.xl),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .start,
          children: [
            Text('Paper', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: InkSpace.lg),
            Row(
              mainAxisAlignment: .spaceEvenly,
              children: [
                for (final template in PaperTemplate.values)
                  _TemplateOption(
                    template: template,
                    selected: template == current,
                    onTap: () => Navigator.of(context).pop(template),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _TemplateOption extends StatelessWidget {
  const _TemplateOption({
    required this.template,
    required this.selected,
    required this.onTap,
  });

  final PaperTemplate template;
  final bool selected;
  final VoidCallback onTap;

  static const _labels = {
    PaperTemplate.blank: 'Blank',
    PaperTemplate.lined: 'Lined',
    PaperTemplate.grid: 'Grid',
    PaperTemplate.dotted: 'Dotted',
  };

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '${_labels[template]} paper',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(InkSpace.sm),
          child: Column(
            mainAxisSize: .min,
            children: [
              Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: selected ? InkColors.primary : InkColors.divider,
                    width: selected ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: CustomPaint(
                    size: const Size(72, 94),
                    painter: _TemplatePreviewPainter(template),
                  ),
                ),
              ),
              const SizedBox(height: InkSpace.sm),
              Text(
                _labels[template]!,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? InkColors.primary : InkColors.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TemplatePreviewPainter extends CustomPainter {
  _TemplatePreviewPainter(this.template);

  final PaperTemplate template;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final line = Paint()
      ..color = const Color(0xFFDDE5E7)
      ..strokeWidth = 1;
    const step = 12.0;
    switch (template) {
      case PaperTemplate.blank:
        break;
      case PaperTemplate.lined:
        for (var y = step * 1.5; y < size.height - 4; y += step) {
          canvas.drawLine(Offset(6, y), Offset(size.width - 6, y), line);
        }
      case PaperTemplate.grid:
        for (var y = step; y < size.height; y += step) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
        }
        for (var x = step; x < size.width; x += step) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
        }
      case PaperTemplate.dotted:
        final dot = Paint()..color = const Color(0xFFCBD5D8);
        for (var y = step; y < size.height; y += step) {
          for (var x = step; x < size.width; x += step) {
            canvas.drawCircle(Offset(x, y), 1, dot);
          }
        }
    }
  }

  @override
  bool shouldRepaint(_TemplatePreviewPainter oldDelegate) =>
      oldDelegate.template != template;
}
