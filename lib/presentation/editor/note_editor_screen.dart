import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/theme/tokens.dart';
import '../../domain/entities/image_object.dart';
import '../../domain/entities/note_document.dart';
import '../../domain/repositories/note_repository.dart';
import '../../domain/services/pdf_renderer.dart';
import '../../domain/util/id_generator.dart';
import 'bloc/note_editor_bloc.dart';
import 'bloc/toolbar_cubit.dart';
import 'canvas/ink_canvas.dart';
import 'engine/active_stroke_controller.dart';
import 'engine/document_layout.dart';
import 'engine/image_raster_cache.dart';
import 'engine/page_camera.dart';
import 'engine/pdf_background_cache.dart';
import 'widgets/editor_toolbar.dart';
import 'widgets/page_chip.dart';
import 'widgets/page_turn_hint.dart';
import 'widgets/selection_bar.dart';
import 'widgets/template_sheet.dart';
import 'widgets/zoom_chip.dart';

/// Picks images for insertion; injectable so tests don't need the
/// platform plugin.
typedef PickImageBytes = Future<({ui.Image decoded, List<int> bytes})?>
    Function(ImageSource source);

class NoteEditorScreen extends StatefulWidget {
  const NoteEditorScreen({
    super.key,
    required this.noteId,
    this.title,
    this.pickImage,
  });

  final String noteId;
  final String? title;
  final PickImageBytes? pickImage;

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final _activeStroke = ActiveStrokeController();
  final _imageCache = ImageRasterCache();
  final _zoomScale = ValueNotifier<double?>(null);
  final _pageTurnProgress = ValueNotifier<double>(0);
  PageCamera? _camera;
  PdfBackgroundCache? _pdfCache;
  NoteEditorBloc? _bloc;
  DocumentLayout _layout = DocumentLayout(const []);

  /// Animated scroll for page navigation (chip arrows, new page).
  late final AnimationController _scrollAnimation;
  double _scrollBegin = 0;
  double _scrollTarget = 0;

  NoteRepository? get _repository {
    try {
      return RepositoryProvider.of<NoteRepository>(context, listen: false);
    } on Object {
      return null;
    }
  }

  PdfRenderer? get _pdfRenderer {
    try {
      return RepositoryProvider.of<PdfRenderer>(context, listen: false);
    } on Object {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    )..addListener(_onScrollTick);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _bloc?.add(const EditorFlushRequested());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollAnimation.dispose();
    _activeStroke.dispose();
    _imageCache.dispose();
    _zoomScale.dispose();
    _pageTurnProgress.dispose();
    _camera?.dispose();
    _pdfCache?.dispose();
    super.dispose();
  }

  PageCamera _cameraFor(NoteDocument doc) {
    _layout = DocumentLayout(doc.pages);
    final first = doc.pages.first.spec;
    final camera = _camera ??= PageCamera(
      initialContentSize: _layout.size,
      initialFitSize: Size(first.displayWidth, first.displayHeight),
      startAtActualSize: doc.kind == NoteKind.whiteboard,
      pageBound: doc.kind != NoteKind.whiteboard,
    );
    camera.setContentSize(_layout.size);
    return camera;
  }

  // --- Page navigation: animated scroll through the document ---

  void _onScrollTick() {
    final t = Curves.easeInOutCubic.transform(_scrollAnimation.value);
    _camera?.setVerticalOffset(ui.lerpDouble(_scrollBegin, _scrollTarget, t)!);
  }

  /// Scrolls the document so [index]'s page top sits under the toolbar.
  void _scrollToPage(int index) {
    final camera = _camera;
    final doc = _bloc?.state.document;
    if (camera == null || doc == null || doc.pages.isEmpty) return;
    final layout = DocumentLayout(doc.pages);
    final rect = layout.pageRects[index.clamp(0, doc.pages.length - 1)];
    _scrollBegin = camera.verticalOffset;
    _scrollTarget = PageCamera.pageMargin - rect.top * camera.scale;
    _scrollAnimation
      ..stop()
      ..forward(from: 0);
  }

  /// Chip navigation: update the bloc and glide to the page.
  void _goToPage(NoteEditorBloc bloc, int index) {
    bloc.add(EditorPageChanged(index));
    _scrollToPage(index);
  }

  /// Pull-past-the-end: append a page (the bloc inserts after the current
  /// page, so route to the last page first).
  void _addPageAtEnd(NoteEditorBloc bloc) {
    final doc = bloc.state.document;
    if (doc == null) return;
    final last = doc.pages.length - 1;
    if (bloc.state.pageIndex != last) bloc.add(EditorPageChanged(last));
    bloc.add(const EditorPageAdded());
  }

  PdfBackgroundCache? _pdfCacheFor(NoteDocument doc) {
    final path = doc.sourcePdfPath;
    final renderer = _pdfRenderer;
    if (path == null || renderer == null) return null;
    return _pdfCache ??= PdfBackgroundCache(renderer: renderer, pdfPath: path);
  }

  Future<void> _insertImage(BuildContext context, ImageSource source) async {
    final bloc = context.read<NoteEditorBloc>();
    final repo = _repository;
    final picker = widget.pickImage ?? _pickWithImagePicker;
    final picked = await picker(source);
    if (picked == null || repo == null || !mounted) return;

    final page = bloc.state.currentPage;
    if (page == null) return;
    final assetPath = await repo.importImageBytes(
        widget.noteId, Uint8List.fromList(picked.bytes));

    // Fit within a third of the page, centered.
    final maxSide = page.spec.width / 3;
    final scale = (maxSide / picked.decoded.width)
        .clamp(0.0, maxSide / picked.decoded.height)
        .clamp(0.01, 1.0);
    final w = picked.decoded.width * scale;
    final h = picked.decoded.height * scale;
    bloc.add(EditorImageAdded(ImageObject(
      id: newId('img'),
      assetPath: assetPath,
      x: (page.spec.width - w) / 2,
      y: (page.spec.height - h) / 2,
      width: w,
      height: h,
    )));
  }

  static Future<({ui.Image decoded, List<int> bytes})?> _pickWithImagePicker(
      ImageSource source) async {
    final file = await ImagePicker().pickImage(source: source);
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return (decoded: frame.image, bytes: bytes);
  }

  void _showImageSourceMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: .min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: InkColors.ink),
              title: const Text('From gallery'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _insertImage(context, ImageSource.gallery);
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.photo_camera_outlined, color: InkColors.ink),
              title: const Text('Take photo'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _insertImage(context, ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => _bloc = NoteEditorBloc(
            noteId: widget.noteId,
            repository: _repository,
          ),
        ),
        BlocProvider(create: (_) => ToolbarCubit()),
      ],
      child: BlocConsumer<NoteEditorBloc, NoteEditorState>(
        listenWhen: (prev, next) =>
            prev.document != null &&
            next.document != null &&
            prev.document!.pages.length < next.document!.pages.length,
        listener: (context, state) {
          _pageTurnProgress.value = 0;
          // A page was inserted after the current one — glide down to it
          // once the new layout has been built.
          final target = (state.pageIndex + 1)
              .clamp(0, state.document!.pages.length - 1);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _scrollToPage(target);
          });
        },
        builder: (context, editorState) {
          if (editorState.status != EditorStatus.ready ||
              editorState.document == null) {
            return const Scaffold(
              backgroundColor: InkColors.backdrop,
              body: Center(
                child: CircularProgressIndicator(color: InkColors.primary),
              ),
            );
          }
          final doc = editorState.document!;
          final isWhiteboard = doc.kind == NoteKind.whiteboard;
          final page = editorState.currentPage!;
          final camera = _cameraFor(doc);
          final pdfCache = _pdfCacheFor(doc);

          return BlocBuilder<ToolbarCubit, ToolbarState>(
            builder: (context, toolbarState) {
              final editorBloc = context.read<NoteEditorBloc>();
              return Scaffold(
                backgroundColor: InkColors.backdrop,
                body: Column(
                  children: [
                    EditorToolbar(
                      title: widget.title ??
                          (isWhiteboard ? 'Whiteboard' : 'Untitled note'),
                      tool: toolbarState.tool,
                      color: toolbarState.color,
                      widthIndex: toolbarState.widthIndex,
                      eraserMode: toolbarState.eraserMode,
                      eraserRadius: toolbarState.eraserRadius,
                      canUndo: editorState.canUndo,
                      canRedo: editorState.canRedo,
                      canClear: page.strokes.isNotEmpty ||
                          page.images.isNotEmpty,
                      showPageActions: !isWhiteboard,
                      onBack: () => context.canPop()
                          ? context.pop()
                          : context.go('/'),
                      onToolSelected: context.read<ToolbarCubit>().selectTool,
                      onColorSelected: (color) {
                        context.read<ToolbarCubit>().selectColor(color);
                        if (editorState.selectedStrokeIds.isNotEmpty) {
                          editorBloc.add(EditorSelectionRecolored(color));
                        }
                      },
                      onWidthSelected:
                          context.read<ToolbarCubit>().selectWidth,
                      onEraserModeChanged:
                          context.read<ToolbarCubit>().setEraserMode,
                      onEraserRadiusChanged:
                          context.read<ToolbarCubit>().setEraserRadius,
                      onInsertImage: () => _showImageSourceMenu(context),
                      onUndo: () =>
                          editorBloc.add(const EditorUndoRequested()),
                      onRedo: () =>
                          editorBloc.add(const EditorRedoRequested()),
                      onAddPage: () =>
                          editorBloc.add(const EditorPageAdded()),
                      onPaperStyle: () async {
                        final template = await showTemplateSheet(context,
                            current: page.spec.template);
                        if (template != null) {
                          editorBloc.add(EditorTemplateChanged(template));
                        }
                      },
                      onRotatePage: () =>
                          editorBloc.add(const EditorPageRotated()),
                      onClearPage: () =>
                          editorBloc.add(const EditorPageCleared()),
                    ),
                    Expanded(
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: InkCanvas(
                              camera: camera,
                              activeStroke: _activeStroke,
                              pages: doc.pages,
                              pageIndex: editorState.pageIndex,
                              layout: _layout,
                              revision: editorState.revision,
                              tool: toolbarState.tool,
                              penColor: toolbarState.color,
                              penWidth: toolbarState.width,
                              eraserMode: toolbarState.eraserMode,
                              eraserRadius: toolbarState.eraserRadius,
                              selectedStrokeIds:
                                  editorState.selectedStrokeIds,
                              selectedImageId: editorState.selectedImageId,
                              imageCache: _imageCache,
                              isWhiteboard: isWhiteboard,
                              pdfCache: pdfCache,
                              canAddPage: !isWhiteboard,
                              onCurrentPageChanged: (index) => editorBloc
                                  .add(EditorPageChanged(index)),
                              onAddPageRequested: () =>
                                  _addPageAtEnd(editorBloc),
                              onOverscrollChanged: (progress) =>
                                  _pageTurnProgress.value = progress,
                              onStrokeCommitted: (stroke) => editorBloc
                                  .add(EditorStrokeCommitted(stroke)),
                              onErased: (removed, added) => editorBloc
                                  .add(EditorStrokesErased(removed, added)),
                              onSelectionChanged: (ids, imageId) =>
                                  editorBloc.add(EditorSelectionChanged(ids,
                                      imageId: imageId)),
                              onSelectionTransformed: (before, after) =>
                                  editorBloc.add(EditorSelectionTransformed(
                                      before, after)),
                              onImageTransformed: (before, after) =>
                                  editorBloc.add(
                                      EditorImageTransformed(before, after)),
                              onZoomChanged: (scale) =>
                                  _zoomScale.value = scale,
                            ),
                          ),
                          if (!isWhiteboard)
                            Positioned.fill(
                              child: IgnorePointer(
                                child: PageTurnHint(
                                    progress: _pageTurnProgress),
                              ),
                            ),
                          Positioned(
                            top: InkSpace.lg,
                            right: InkSpace.lg,
                            child: ZoomChip(scaleNotifier: _zoomScale),
                          ),
                          if (editorState.hasSelection)
                            Positioned(
                              top: InkSpace.md,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: SelectionBar(
                                  strokeCount:
                                      editorState.selectedStrokeIds.length,
                                  isImage:
                                      editorState.selectedImageId != null &&
                                          editorState
                                              .selectedStrokeIds.isEmpty,
                                  selectionColor: page.strokes
                                          .where((s) => editorState
                                              .selectedStrokeIds
                                              .contains(s.id))
                                          .firstOrNull
                                          ?.color ??
                                      toolbarState.color,
                                  onRecolor: (color) => editorBloc
                                      .add(EditorSelectionRecolored(color)),
                                  onDelete: () => editorBloc
                                      .add(const EditorSelectionDeleted()),
                                  onDismiss: () => editorBloc.add(
                                      const EditorSelectionChanged({},
                                          imageId: null)),
                                ),
                              ),
                            ),
                          if (!isWhiteboard)
                            Positioned(
                              bottom: InkSpace.lg,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: PageChip(
                                  pageIndex: editorState.pageIndex,
                                  pageCount: doc.pages.length,
                                  onPageChanged: (index) =>
                                      _goToPage(editorBloc, index),
                                  onAddPage: () => editorBloc
                                      .add(const EditorPageAdded()),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
