import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/tokens.dart';
import '../../domain/entities/folder.dart';
import '../../domain/entities/note_document.dart';
import '../../domain/repositories/library_repository.dart';
import 'bloc/library_bloc.dart';

/// Library: folder tree sidebar + note grid. `/` is the root;
/// `/folder/:id` is the same surface scoped to a folder.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key, this.folderId});

  final String? folderId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => LibraryBloc(
        repository: context.read<LibraryRepository>(),
      )..add(LibraryStarted(folderId)),
      child: BlocListener<LibraryBloc, LibraryState>(
        listenWhen: (prev, next) =>
            next.openNoteId != null && prev.openNoteId != next.openNoteId,
        listener: (context, state) {
          final note =
              state.notes.where((n) => n.id == state.openNoteId).firstOrNull;
          final isWhiteboard = note?.kind == NoteKind.whiteboard ||
              state.openNoteId!.startsWith('wb-');
          context.go(isWhiteboard
              ? '/whiteboard/${state.openNoteId}'
              : '/note/${state.openNoteId}');
        },
        child: const Scaffold(
          backgroundColor: InkColors.backdrop,
          body: SafeArea(
            child: Row(
              crossAxisAlignment: .stretch,
              children: [
                _Sidebar(),
                Expanded(child: _NotesPane()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- Sidebar ---

/// Collapsed folder ids live at module scope: each navigation rebuilds the
/// screen (and its bloc), but the user's expand/collapse choices should
/// survive for the whole session.
final Set<String> _sessionCollapsedFolders = {};

class _Sidebar extends StatefulWidget {
  const _Sidebar();

  @override
  State<_Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<_Sidebar> {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      decoration: const BoxDecoration(
        color: InkColors.chrome,
        border: Border(right: BorderSide(color: InkColors.divider)),
      ),
      child: BlocBuilder<LibraryBloc, LibraryState>(
        builder: (context, state) {
          return Column(
            crossAxisAlignment: .start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    InkSpace.xl, InkSpace.xl, InkSpace.xl, InkSpace.lg),
                child: Text(
                  'NotePinly',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: InkColors.ink,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              _FolderTile(
                name: 'All notes',
                icon: Icons.home_outlined,
                depth: 0,
                selected: state.folderId == null,
                onTap: () => context.go('/'),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: InkSpace.lg),
                  children: [
                    ..._folderTree(context, state, null, 0),
                  ],
                ),
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.all(InkSpace.sm),
                child: Row(
                  children: [
                    TextButton.icon(
                      onPressed: () => _promptNewFolder(context),
                      icon: const Icon(Icons.create_new_folder_outlined,
                          size: 20, color: InkColors.ink),
                      label: const Text('New folder',
                          style: TextStyle(color: InkColors.ink)),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.settings_outlined, size: 20),
                      tooltip: 'Settings',
                      color: InkColors.inkMuted,
                      onPressed: () => context.go('/settings'),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _folderTree(
      BuildContext context, LibraryState state, String? parentId, int depth) {
    final children = state.childrenOf(parentId);
    return [
      for (final folder in children) _folderNode(context, state, folder, depth),
    ];
  }

  /// One folder plus its (collapsible) subtree. The subtree animates open
  /// and closed; the chevron only appears once the folder has children.
  Widget _folderNode(
      BuildContext context, LibraryState state, Folder folder, int depth) {
    final hasChildren = state.childrenOf(folder.id).isNotEmpty;
    final expanded = !_sessionCollapsedFolders.contains(folder.id);
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        _FolderTile(
          name: folder.name,
          icon: Icons.folder_outlined,
          depth: depth,
          selected: state.folderId == folder.id,
          onTap: () => context.go('/folder/${folder.id}'),
          expanded: hasChildren ? expanded : null,
          onToggleExpanded: hasChildren
              ? () => setState(() {
                    if (!_sessionCollapsedFolders.remove(folder.id)) {
                      _sessionCollapsedFolders.add(folder.id);
                    }
                  })
              : null,
          menu: [
            MenuItemButton(
              onPressed: () => _promptRenameFolder(context, folder),
              child: const Text('Rename'),
            ),
            MenuItemButton(
              onPressed: () => _promptNewFolder(context, parentId: folder.id),
              child: const Text('New subfolder'),
            ),
            MenuItemButton(
              onPressed: () => _confirmDeleteFolder(context, folder),
              child: const Text('Delete'),
            ),
          ],
        ),
        ClipRect(
          child: AnimatedSize(
            duration: InkDurations.medium,
            curve: Curves.easeInOutCubic,
            alignment: Alignment.topCenter,
            child: hasChildren && expanded
                ? Column(
                    crossAxisAlignment: .stretch,
                    children: _folderTree(context, state, folder.id, depth + 1),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ),
      ],
    );
  }

  void _promptNewFolder(BuildContext context, {String? parentId}) {
    final bloc = context.read<LibraryBloc>();
    _promptForText(context, title: 'New folder', hint: 'Folder name')
        .then((name) {
      if (name != null && name.trim().isNotEmpty) {
        // Reveal the new subfolder even if its parent was collapsed.
        if (parentId != null && mounted) {
          setState(() => _sessionCollapsedFolders.remove(parentId));
        }
        bloc.add(LibraryFolderCreated(name.trim(), parentId: parentId));
      }
    });
  }

  void _promptRenameFolder(BuildContext context, Folder folder) {
    final bloc = context.read<LibraryBloc>();
    _promptForText(context,
            title: 'Rename folder', hint: 'Folder name', initial: folder.name)
        .then((name) {
      if (name != null && name.trim().isNotEmpty) {
        bloc.add(LibraryFolderRenamed(folder.id, name.trim()));
      }
    });
  }

  void _confirmDeleteFolder(BuildContext context, Folder folder) {
    final bloc = context.read<LibraryBloc>();
    showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete "${folder.name}"?'),
        content: const Text(
            'Notes and subfolders inside move up a level — nothing is lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed ?? false) bloc.add(LibraryFolderDeleted(folder.id));
    });
  }
}

class _FolderTile extends StatelessWidget {
  const _FolderTile({
    required this.name,
    required this.icon,
    required this.depth,
    required this.selected,
    required this.onTap,
    this.expanded,
    this.onToggleExpanded,
    this.menu,
  });

  final String name;
  final IconData icon;
  final int depth;
  final bool selected;
  final VoidCallback onTap;

  /// Non-null only for folders with subfolders; shows the rotating chevron.
  final bool? expanded;
  final VoidCallback? onToggleExpanded;
  final List<Widget>? menu;

  @override
  Widget build(BuildContext context) {
    final color = selected ? InkColors.primary : InkColors.ink;
    final tile = InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: InkDurations.fast,
        curve: Curves.easeOut,
        height: 44,
        padding: EdgeInsets.only(left: InkSpace.xs + depth * 20.0, right: 4),
        decoration: BoxDecoration(
          color: selected ? InkColors.primaryTint : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              height: 44,
              child: expanded == null
                  ? null
                  : InkResponse(
                      onTap: onToggleExpanded,
                      radius: 14,
                      child: Semantics(
                        button: true,
                        label: expanded!
                            ? 'Collapse subfolders'
                            : 'Expand subfolders',
                        child: AnimatedRotation(
                          turns: expanded! ? 0.25 : 0,
                          duration: InkDurations.fast,
                          curve: Curves.easeOutCubic,
                          child: const Icon(Icons.chevron_right_rounded,
                              size: 18, color: InkColors.inkMuted),
                        ),
                      ),
                    ),
            ),
            Icon(icon, size: 20, color: color),
            const SizedBox(width: InkSpace.md),
            Expanded(
              child: Text(
                name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: color,
                ),
              ),
            ),
            if (menu != null)
              MenuAnchor(
                menuChildren: menu!,
                builder: (context, controller, _) => IconButton(
                  icon: const Icon(Icons.more_vert_rounded, size: 18),
                  color: InkColors.inkMuted,
                  tooltip: 'Folder options',
                  onPressed: () =>
                      controller.isOpen ? controller.close() : controller.open(),
                ),
              ),
          ],
        ),
      ),
    );
    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: InkSpace.sm, vertical: 1),
      child: tile,
    );
  }
}

// --- Notes pane ---

class _NotesPane extends StatelessWidget {
  const _NotesPane();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LibraryBloc, LibraryState>(
      builder: (context, state) {
        final folderName = state.currentFolder?.name ?? 'All notes';
        return Column(
          crossAxisAlignment: .start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  InkSpace.xxl, InkSpace.xl, InkSpace.xxl, InkSpace.lg),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      folderName,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: InkColors.ink,
                        letterSpacing: -0.2,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => context
                        .read<LibraryBloc>()
                        .add(const LibraryNoteCreated(NoteKind.whiteboard)),
                    icon: const Icon(Icons.dashboard_outlined, size: 19),
                    label: const Text('Whiteboard'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: InkColors.ink,
                      side: const BorderSide(color: InkColors.divider),
                      minimumSize: const Size(48, 44),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(width: InkSpace.md),
                  FilledButton.icon(
                    onPressed: () => context
                        .read<LibraryBloc>()
                        .add(const LibraryNoteCreated(NoteKind.note)),
                    icon: const Icon(Icons.edit_rounded, size: 19),
                    label: const Text('New note'),
                  ),
                  MenuAnchor(
                    menuChildren: [
                      MenuItemButton(
                        leadingIcon: const Icon(Icons.picture_as_pdf_outlined,
                            size: 20),
                        onPressed: () =>
                            ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                'PDF import needs a file picker package — pending approval.'),
                          ),
                        ),
                        child: const Text('New from PDF…'),
                      ),
                    ],
                    builder: (context, controller, _) => IconButton(
                      icon: const Icon(Icons.more_vert_rounded),
                      tooltip: 'More',
                      color: InkColors.ink,
                      onPressed: () => controller.isOpen
                          ? controller.close()
                          : controller.open(),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: state.notes.isEmpty
                  ? const _EmptyState()
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(
                          InkSpace.xxl, 0, InkSpace.xxl, InkSpace.xxl),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 220,
                        mainAxisSpacing: InkSpace.xl,
                        crossAxisSpacing: InkSpace.xl,
                        childAspectRatio: 0.72,
                      ),
                      itemCount: state.notes.length,
                      itemBuilder: (context, i) =>
                          _NoteCard(note: state.notes[i]),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: .center,
        children: const [
          Icon(Icons.edit_rounded, size: 40, color: InkColors.inkDisabled),
          SizedBox(height: InkSpace.lg),
          Text(
            'Nothing here yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: InkColors.ink,
            ),
          ),
          SizedBox(height: InkSpace.xs),
          Text(
            'Create a note and start writing — it saves itself.',
            style: TextStyle(fontSize: 14, color: InkColors.inkMuted),
          ),
        ],
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.note});

  final NoteMeta note;

  @override
  Widget build(BuildContext context) {
    final isWhiteboard = note.kind == NoteKind.whiteboard;
    final thumbFile =
        note.thumbnailPath == null ? null : File(note.thumbnailPath!);
    final hasThumb = thumbFile?.existsSync() ?? false;

    return Semantics(
      button: true,
      label: note.title,
      child: InkWell(
        onTap: () => context.go(
          isWhiteboard ? '/whiteboard/${note.id}' : '/note/${note.id}',
          extra: note.title,
        ),
        onLongPress: () => _showNoteMenu(context),
        borderRadius: BorderRadius.circular(10),
        child: Column(
          crossAxisAlignment: .start,
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: InkColors.divider),
                ),
                child: hasThumb
                    ? Image.file(
                        thumbFile!,
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                        key: ValueKey(note.updatedAt),
                      )
                    : Center(
                        child: Icon(
                          isWhiteboard
                              ? Icons.dashboard_outlined
                              : Icons.edit_rounded,
                          size: 28,
                          color: InkColors.inkDisabled,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: InkSpace.sm),
            Row(
              children: [
                Expanded(
                  child: Text(
                    note.title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: InkColors.ink,
                    ),
                  ),
                ),
                MenuAnchor(
                  menuChildren: _menuItems(context),
                  builder: (context, controller, _) => InkResponse(
                    onTap: () =>
                        controller.isOpen ? controller.close() : controller.open(),
                    radius: 16,
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.more_horiz_rounded,
                          size: 18, color: InkColors.inkMuted),
                    ),
                  ),
                ),
              ],
            ),
            Text(
              _relativeDate(note.updatedAt),
              style: const TextStyle(fontSize: 12, color: InkColors.inkMuted),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _menuItems(BuildContext context) => [
        MenuItemButton(
          onPressed: () => _promptRename(context),
          child: const Text('Rename'),
        ),
        MenuItemButton(
          onPressed: () => _promptMove(context),
          child: const Text('Move to…'),
        ),
        MenuItemButton(
          onPressed: () => _confirmDelete(context),
          child: const Text('Delete'),
        ),
      ];

  void _showNoteMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: .min,
          children: [
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('Rename'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _promptRename(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_move_outlined),
              title: const Text('Move to…'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _promptMove(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('Delete'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _confirmDelete(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _promptRename(BuildContext context) {
    final bloc = context.read<LibraryBloc>();
    _promptForText(context,
            title: 'Rename', hint: 'Title', initial: note.title)
        .then((title) {
      if (title != null && title.trim().isNotEmpty) {
        bloc.add(LibraryNoteRenamed(note.id, title.trim()));
      }
    });
  }

  void _promptMove(BuildContext context) {
    final bloc = context.read<LibraryBloc>();
    final folders = bloc.state.folders;
    showDialog<({String? folderId})>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Move to'),
        children: [
          SimpleDialogOption(
            onPressed: () =>
                Navigator.of(dialogContext).pop((folderId: null)),
            child: const Row(children: [
              Icon(Icons.home_outlined, size: 20, color: InkColors.ink),
              SizedBox(width: InkSpace.md),
              Text('All notes'),
            ]),
          ),
          for (final folder in folders)
            SimpleDialogOption(
              onPressed: () =>
                  Navigator.of(dialogContext).pop((folderId: folder.id)),
              child: Row(children: [
                const Icon(Icons.folder_outlined,
                    size: 20, color: InkColors.ink),
                const SizedBox(width: InkSpace.md),
                Expanded(
                    child:
                        Text(folder.name, overflow: TextOverflow.ellipsis)),
              ]),
            ),
        ],
      ),
    ).then((choice) {
      if (choice != null) bloc.add(LibraryNoteMoved(note.id, choice.folderId));
    });
  }

  void _confirmDelete(BuildContext context) {
    final bloc = context.read<LibraryBloc>();
    showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete "${note.title}"?'),
        content: const Text('This permanently removes the note and its ink.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed ?? false) bloc.add(LibraryNoteDeleted(note.id));
    });
  }

  static String _relativeDate(DateTime time) {
    final delta = DateTime.now().difference(time);
    if (delta.inMinutes < 1) return 'Just now';
    if (delta.inHours < 1) return '${delta.inMinutes}m ago';
    if (delta.inDays < 1) return '${delta.inHours}h ago';
    if (delta.inDays < 7) return '${delta.inDays}d ago';
    return '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';
  }
}

// --- Shared text prompt ---

Future<String?> _promptForText(
  BuildContext context, {
  required String title,
  required String hint,
  String? initial,
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(controller.text),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}
