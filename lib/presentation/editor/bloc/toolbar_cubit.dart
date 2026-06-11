import 'dart:ui' show Color;

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/theme/tokens.dart';
import '../../../domain/entities/editor_tool.dart';
import '../engine/eraser_engine.dart';

final class ToolbarState extends Equatable {
  const ToolbarState({
    this.tool = EditorTool.pen,
    this.color = const Color(0xFF161C1E),
    this.widthIndex = 1,
    this.eraserMode = EraserMode.stroke,
    this.eraserRadius = 12.0,
  });

  final EditorTool tool;

  /// Active ink color — a palette swatch or a custom-picked color.
  final Color color;
  final int widthIndex;
  final EraserMode eraserMode;

  /// Page-logical radius of the eraser circle.
  final double eraserRadius;

  double get width => penWidthPresets[widthIndex];

  bool get isCustomColor => !InkColors.penInks.contains(color);

  ToolbarState copyWith({
    EditorTool? tool,
    Color? color,
    int? widthIndex,
    EraserMode? eraserMode,
    double? eraserRadius,
  }) =>
      ToolbarState(
        tool: tool ?? this.tool,
        color: color ?? this.color,
        widthIndex: widthIndex ?? this.widthIndex,
        eraserMode: eraserMode ?? this.eraserMode,
        eraserRadius: eraserRadius ?? this.eraserRadius,
      );

  @override
  List<Object?> get props => [tool, color, widthIndex, eraserMode, eraserRadius];
}

class ToolbarCubit extends Cubit<ToolbarState> {
  ToolbarCubit() : super(const ToolbarState());

  void selectTool(EditorTool tool) => emit(state.copyWith(tool: tool));

  void selectColor(Color color) => emit(state.copyWith(color: color));

  void selectWidth(int index) {
    if (index < 0 || index >= penWidthPresets.length) return;
    emit(state.copyWith(widthIndex: index));
  }

  void setEraserMode(EraserMode mode) => emit(state.copyWith(eraserMode: mode));

  void setEraserRadius(double radius) =>
      emit(state.copyWith(eraserRadius: clampEraserRadius(radius)));
}
