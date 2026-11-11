import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/not_found_view.dart';
import '../../modules/downloader/domain/entities/media_info.dart';
import '../../modules/downloader/presentation/views/downloads_view.dart';
import '../../modules/downloader/presentation/views/home_view.dart';
import '../../modules/downloader/presentation/views/playlist_view.dart';
import '../../modules/downloader/presentation/views/widgets/downloads_badge.dart';
import '../../modules/library/presentation/views/library_view.dart';
import '../../modules/library/presentation/views/player_view.dart';
import '../../modules/settings/presentation/views/settings_view.dart';
import '../gallery/gallery_view.dart';
import '../shell/app_shell.dart';
import 'app_routes.dart';

/// The one router, shared by `App`. A test builds its own with
/// `AppRouter.create()`.
final routerProvider = Provider<GoRouter>((ref) {
  final router = AppRouter.create();
  ref.onDispose(router.dispose);
  return router;
});

abstract final class AppRouter {
  static GoRouter create({String initialLocation = AppRoutes.home}) => GoRouter(
    initialLocation: initialLocation,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) =>
            AppShell(shell: shell, downloadsBadge: const DownloadsBadge()),
        branches: [
          _branch(AppRoutes.home, const HomeView()),
          _branch(AppRoutes.downloads, const DownloadsView()),
          _branch(AppRoutes.library, const LibraryView()),
          _branch(AppRoutes.settings, const SettingsView()),
        ],
      ),
      // Outside the shell: the player covers the tab bar.
      GoRoute(path: AppRoutes.player, builder: _player),
      GoRoute(path: AppRoutes.playlist, builder: _playlist),
      // A device-check tool; the plain kDebugMode guard lets release builds
      // tree-shake the gallery.
      if (kDebugMode)
        GoRoute(
          path: AppRoutes.gallery,
          builder: (_, _) => const GalleryView(),
        ),
    ],
    errorBuilder: (context, state) => _notFound(context),
  );

  static StatefulShellBranch _branch(String path, Widget view) =>
      StatefulShellBranch(
        routes: [GoRoute(path: path, builder: (_, _) => view)],
      );

  static Widget _player(BuildContext context, GoRouterState state) {
    final params = state.uri.queryParameters;
    final uri = params['uri'];
    if (uri == null || uri.isEmpty) return _notFound(context);
    return PlayerView(uri: uri, title: params['title'] ?? '');
  }

  static Widget _playlist(BuildContext context, GoRouterState state) =>
      switch (state.extra) {
        final MediaInfo info => PlaylistView(info: info),
        _ => _notFound(context),
      };

  static Widget _notFound(BuildContext context) =>
      NotFoundView(onHome: () => context.go(AppRoutes.home));
}
