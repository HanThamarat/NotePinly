import 'package:go_router/go_router.dart';

import '../domain/repositories/library_repository.dart';
import '../presentation/editor/note_editor_screen.dart';
import '../presentation/library/library_screen.dart';
import '../presentation/settings/settings_screen.dart';

/// Routes per ARCHITECTURE.md. Every navigation records itself so the
/// app reopens where it left off (restored via [initialLocation]).
GoRouter buildRouter({
  LibraryRepository? library,
  String initialLocation = '/',
}) {
  void remember(String location) {
    library?.setLastRoute(location);
  }

  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) {
          remember('/');
          return const LibraryScreen();
        },
        routes: [
          GoRoute(
            path: 'folder/:id',
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              remember('/folder/$id');
              return LibraryScreen(folderId: id);
            },
          ),
          GoRoute(
            path: 'note/:id',
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              remember('/note/$id');
              return NoteEditorScreen(
                noteId: id,
                title: state.extra as String?,
              );
            },
          ),
          GoRoute(
            path: 'whiteboard/:id',
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              remember('/whiteboard/$id');
              return NoteEditorScreen(
                noteId: id,
                title: state.extra as String?,
              );
            },
          ),
          GoRoute(
            path: 'settings',
            builder: (context, state) => const SettingsScreen(),
          ),
        ],
      ),
    ],
  );
}
