import 'package:flutter/material.dart';

import '../../../app/theme/tokens.dart';
import '../../../domain/entities/editor_tool.dart';
import '../engine/eraser_engine.dart';
import 'color_picker.dart';

/// The single thin chrome bar: navigation + title (left), tool cluster +
/// inks + width (center), undo/redo + overflow (right). Re-tapping the
/// active eraser opens its options popover.
class EditorToolbar extends StatelessWidget {
  const EditorToolbar({
    super.key,
    required this.title,
    required this.tool,
    required this.color,
    required this.widthIndex,
    required this.eraserMode,
    required this.eraserRadius,
    required this.canUndo,
    required this.canRedo,
    required this.canClear,
    required this.showPageActions,
    required this.onBack,
    required this.onToolSelected,
    required this.onColorSelected,
    required this.onWidthSelected,
    required this.onEraserModeChanged,
    required this.onEraserRadiusChanged,
    required this.onInsertImage,
    required this.onUndo,
    required this.onRedo,
    required this.onAddPage,
    required this.onPaperStyle,
    required this.onRotatePage,
    required this.onClearPage,
  });

  final String title;
  final EditorTool tool;
  final Color color;
  final int widthIndex;
  final EraserMode eraserMode;
  final double eraserRadius;
  final bool canUndo;
  final bool canRedo;
  final bool canClear;

  /// Whiteboards hide page-shaped actions (add page, paper, rotate).
  final bool showPageActions;
  final VoidCallback onBack;
  final ValueChanged<EditorTool> onToolSelected;
  final ValueChanged<Color> onColorSelected;
  final ValueChanged<int> onWidthSelected;
  final ValueChanged<EraserMode> onEraserModeChanged;
  final ValueChanged<double> onEraserRadiusChanged;
  final VoidCallback onInsertImage;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onAddPage;
  final VoidCallback onPaperStyle;
  final VoidCallback onRotatePage;
  final VoidCallback onClearPage;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: InkColors.chrome,
      child: SafeArea(
        bottom: false,
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: InkSpace.sm),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: InkColors.divider)),
          ),
          child: NavigationToolbar(
            middleSpacing: InkSpace.lg,
            leading: Row(
              mainAxisSize: .min,
              children: [
                _BarIconButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: 'Library',
                  onPressed: onBack,
                ),
                const SizedBox(width: InkSpace.xs),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            middle: Row(
              mainAxisSize: .min,
              children: [
                _ToolButton(
                  icon: Icons.edit_rounded,
                  label: 'Pen',
                  selected: tool == EditorTool.pen,
                  onPressed: () => onToolSelected(EditorTool.pen),
                ),
                _EraserButton(
                  selected: tool == EditorTool.eraser,
                  mode: eraserMode,
                  radius: eraserRadius,
                  onSelected: () => onToolSelected(EditorTool.eraser),
                  onModeChanged: onEraserModeChanged,
                  onRadiusChanged: onEraserRadiusChanged,
                ),
                _ToolButton(
                  icon: Icons.highlight_alt_rounded,
                  label: 'Lasso select',
                  selected: tool == EditorTool.lasso,
                  onPressed: () => onToolSelected(EditorTool.lasso),
                ),
                _ToolButton(
                  icon: Icons.image_outlined,
                  label: 'Insert image',
                  selected: false,
                  onPressed: onInsertImage,
                ),
                const _BarDivider(),
                for (final ink in InkColors.penInks)
                  _ColorSwatch(
                    color: ink,
                    selected: ink == color,
                    onPressed: () => onColorSelected(ink),
                  ),
                CustomColorButton(
                  currentColor: color,
                  isActive: !InkColors.penInks.contains(color),
                  onColorSelected: onColorSelected,
                ),
                const _BarDivider(),
                _WidthButton(
                  widthIndex: widthIndex,
                  inkColor: color,
                  onWidthSelected: onWidthSelected,
                ),
              ],
            ),
            trailing: Row(
              mainAxisSize: .min,
              children: [
                _BarIconButton(
                  icon: Icons.undo_rounded,
                  tooltip: 'Undo',
                  onPressed: canUndo ? onUndo : null,
                ),
                _BarIconButton(
                  icon: Icons.redo_rounded,
                  tooltip: 'Redo',
                  onPressed: canRedo ? onRedo : null,
                ),
                const _BarDivider(),
                MenuAnchor(
                  menuChildren: [
                    if (showPageActions) ...[
                      MenuItemButton(
                        leadingIcon:
                            const Icon(Icons.note_add_outlined, size: 20),
                        onPressed: onAddPage,
                        child: const Text('Add page'),
                      ),
                      MenuItemButton(
                        leadingIcon:
                            const Icon(Icons.grid_4x4_rounded, size: 20),
                        onPressed: onPaperStyle,
                        child: const Text('Paper style…'),
                      ),
                      MenuItemButton(
                        leadingIcon:
                            const Icon(Icons.rotate_90_degrees_cw_outlined,
                                size: 20),
                        onPressed: onRotatePage,
                        child: const Text('Rotate page'),
                      ),
                      const Divider(),
                    ],
                    MenuItemButton(
                      leadingIcon:
                          const Icon(Icons.layers_clear_outlined, size: 20),
                      onPressed: canClear ? onClearPage : null,
                      child: const Text('Clear page'),
                    ),
                  ],
                  builder: (context, menuController, _) => _BarIconButton(
                    icon: Icons.more_horiz_rounded,
                    tooltip: 'More',
                    onPressed: () => menuController.isOpen
                        ? menuController.close()
                        : menuController.open(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BarDivider extends StatelessWidget {
  const _BarDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 22,
      margin: const EdgeInsets.symmetric(horizontal: InkSpace.md),
      color: InkColors.divider,
    );
  }
}

class _BarIconButton extends StatelessWidget {
  const _BarIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon),
      tooltip: tooltip,
      onPressed: onPressed,
      iconSize: 22,
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      color: InkColors.ink,
      disabledColor: InkColors.inkDisabled,
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: InkDurations.fast,
            curve: Curves.easeOutQuart,
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: selected ? InkColors.primaryTint : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon,
                size: 22,
                color: selected ? InkColors.primary : InkColors.ink),
          ),
        ),
      ),
    );
  }
}

/// Eraser tool button. First tap activates; tapping while active opens
/// the options popover (mode + size with live indicator).
class _EraserButton extends StatelessWidget {
  const _EraserButton({
    required this.selected,
    required this.mode,
    required this.radius,
    required this.onSelected,
    required this.onModeChanged,
    required this.onRadiusChanged,
  });

  final bool selected;
  final EraserMode mode;
  final double radius;
  final VoidCallback onSelected;
  final ValueChanged<EraserMode> onModeChanged;
  final ValueChanged<double> onRadiusChanged;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: [
        _EraserOptions(
          mode: mode,
          radius: radius,
          onModeChanged: onModeChanged,
          onRadiusChanged: onRadiusChanged,
        ),
      ],
      builder: (context, menuController, _) => Tooltip(
        message: 'Eraser',
        child: Semantics(
          button: true,
          selected: selected,
          label: 'Eraser',
          child: InkWell(
            onTap: () {
              if (selected) {
                menuController.isOpen
                    ? menuController.close()
                    : menuController.open();
              } else {
                onSelected();
              }
            },
            borderRadius: BorderRadius.circular(10),
            child: AnimatedContainer(
              duration: InkDurations.fast,
              curve: Curves.easeOutQuart,
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: selected ? InkColors.primaryTint : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: _EraserGlyph(
                    color: selected ? InkColors.primary : InkColors.ink),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EraserOptions extends StatefulWidget {
  const _EraserOptions({
    required this.mode,
    required this.radius,
    required this.onModeChanged,
    required this.onRadiusChanged,
  });

  final EraserMode mode;
  final double radius;
  final ValueChanged<EraserMode> onModeChanged;
  final ValueChanged<double> onRadiusChanged;

  @override
  State<_EraserOptions> createState() => _EraserOptionsState();
}

class _EraserOptionsState extends State<_EraserOptions> {
  late EraserMode _mode = widget.mode;
  late double _radius = widget.radius;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(InkSpace.lg),
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .start,
        children: [
          SegmentedButton<EraserMode>(
            segments: const [
              ButtonSegment(
                value: EraserMode.stroke,
                label: Text('Stroke'),
                tooltip: 'Erase whole strokes',
              ),
              ButtonSegment(
                value: EraserMode.area,
                label: Text('Pixel'),
                tooltip: 'Erase parts of strokes',
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (selection) {
              setState(() => _mode = selection.first);
              widget.onModeChanged(selection.first);
            },
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              selectedBackgroundColor: InkColors.primaryTint,
              selectedForegroundColor: InkColors.primary,
              foregroundColor: InkColors.ink,
              textStyle:
                  const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(height: InkSpace.md),
          Row(
            children: [
              SizedBox(
                width: 180,
                child: Slider(
                  value: _radius,
                  min: 4,
                  max: 48,
                  activeColor: InkColors.primary,
                  label: 'Eraser size',
                  onChanged: (v) {
                    setState(() => _radius = v);
                    widget.onRadiusChanged(v);
                  },
                ),
              ),
              // Live size indicator at true scale.
              SizedBox(
                width: 52,
                height: 52,
                child: Center(
                  child: Container(
                    width: _radius.clamp(4, 48),
                    height: _radius.clamp(4, 48),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: InkColors.primaryTint,
                      border: Border.all(color: InkColors.primary, width: 1.5),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.selected,
    required this.onPressed,
  });

  final Color color;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: 'Ink color',
      child: InkResponse(
        onTap: onPressed,
        radius: 20,
        child: SizedBox(
          width: 32,
          height: 44,
          child: Center(
            child: AnimatedContainer(
              duration: InkDurations.fast,
              curve: Curves.easeOutQuart,
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? color : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Center(
                child: Container(
                  width: selected ? 12 : 16,
                  height: selected ? 12 : 16,
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

class _WidthButton extends StatelessWidget {
  const _WidthButton({
    required this.widthIndex,
    required this.inkColor,
    required this.onWidthSelected,
  });

  final int widthIndex;
  final Color inkColor;
  final ValueChanged<int> onWidthSelected;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: [
        for (var i = 0; i < penWidthPresets.length; i++)
          MenuItemButton(
            onPressed: () => onWidthSelected(i),
            trailingIcon: i == widthIndex
                ? const Icon(Icons.check_rounded,
                    size: 18, color: InkColors.primary)
                : const SizedBox(width: 18),
            child: SizedBox(
              width: 96,
              height: 28,
              child: Center(
                child: Container(
                  height: penWidthPresets[i],
                  decoration: BoxDecoration(
                    color: InkColors.ink,
                    borderRadius: BorderRadius.circular(penWidthPresets[i] / 2),
                  ),
                ),
              ),
            ),
          ),
      ],
      builder: (context, menuController, _) => Tooltip(
        message: 'Stroke width',
        child: Semantics(
          button: true,
          label: 'Stroke width',
          child: InkWell(
            onTap: () => menuController.isOpen
                ? menuController.close()
                : menuController.open(),
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 44,
              height: 44,
              child: Center(
                child: Container(
                  width: 20,
                  height: penWidthPresets[widthIndex],
                  decoration: BoxDecoration(
                    color: inkColor,
                    borderRadius:
                        BorderRadius.circular(penWidthPresets[widthIndex] / 2),
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

/// Eraser tool glyph (no eraser in Flutter's bundled Material set).
class _EraserGlyph extends StatelessWidget {
  const _EraserGlyph({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(22, 22),
      painter: _EraserGlyphPainter(color: color),
    );
  }
}

class _EraserGlyphPainter extends CustomPainter {
  _EraserGlyphPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    canvas
      ..translate(c.dx, c.dy + 1)
      ..rotate(-0.6);
    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: 9, height: 14),
      const Radius.circular(2.5),
    );
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..color = color;
    canvas.drawRRect(body, stroke);
    canvas.clipRect(const Rect.fromLTRB(-6, 1.5, 6, 8));
    canvas.drawRRect(body, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_EraserGlyphPainter oldDelegate) =>
      oldDelegate.color != color;
}
