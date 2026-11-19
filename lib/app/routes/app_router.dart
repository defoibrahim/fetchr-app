import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/not_found_view.dart';
import '../../modules/downloader/domain/entities/media_info.dart';
import '../../modules/downloader/presentation/views/downloads_view.dart';
import '../../modules/downloader/presentation/views/home_view.dart';
import '../../modules/downloader/presentation/views/playlist_detail_view.dart';
import '../../modules/downloader/presentation/views/playlist_view.dart';
import '../../modules/downloader/presentation/views/widgets/downloads_badge.dart';
import '../../modules/library/presentation/views/library_playlist_view.dart';
import '../../modules/library/presentation/views/library_view.dart';
import '../../modules/library/presentation/views/player_view.dart';
import '../../modules/settings/presentation/views/settings_view.dart';
import '../gallery/gallery_view.dart';
import '../shell/app_branch_switcher.dart';
import '../shell/app_shell.dart';
import '../shell/tab_scroll.dart';
import 'app_routes.dart';

/// The one router, shared by `App`. A test builds its own with
/// `AppRouter.create()`.
final routerProvider = Provider<GoRouter>((ref) {
  final router = AppRouter.create();
  ref.onDispose(router.dispose);
  return router;
});

abstract final class AppRouter {
  // In tab order.
  static const List<(String, Widget)> _tabs = [
    (AppRoutes.home, HomeView()),
    (AppRoutes.downloads, DownloadsView()),
    (AppRoutes.library, LibraryView()),
    (AppRoutes.settings, SettingsView()),
  ];

  static GoRouter create({String initialLocation = AppRoutes.home}) {
    // One per tab, so a tap on the open tab can reach its page's list.
    final tabs = [
      for (final (path, view) in _tabs)
        (path: path, view: view, top: GlobalKey<TabScrollState>()),
    ];
    return GoRouter(
      initialLocation: initialLocation,
      routes: [
        StatefulShellRoute(
          pageBuilder: (_, state, shell) => _page(
            state,
            AppShell(
              shell: shell,
              downloadsBadge: const DownloadsBadge(),
              onReselect: (index) => tabs[index].top.currentState?.toTop(),
            ),
          ),
          navigatorContainerBuilder: (_, shell, children) => AppBranchSwitcher(
            currentIndex: shell.currentIndex,
            children: children,
          ),
          branches: [for (final t in tabs) _branch(t.path, t.view, t.top)],
        ),
        // Outside the shell: the player covers the tab bar.
        _route(AppRoutes.player, _player),
        _route(AppRoutes.playlist, _playlist),
        _route(AppRoutes.libraryPlaylist, _libraryPlaylist),
        _route(AppRoutes.downloadsPlaylist, _downloadsPlaylist),
        // A device-check tool; the plain kDebugMode guard lets release builds
        // tree-shake the gallery.
        if (kDebugMode)
          _route(AppRoutes.gallery, (_, _) => const GalleryView()),
      ],
      errorPageBuilder: (context, state) => _page(state, _notFound(context)),
    );
  }

  // go_router 18 looks for material_ui's MaterialApp, not Flutter's, so its
  // own pages would be NoTransitionPages: no theme transition, no reduce
  // motion, no predictive back. The routes build Material pages themselves.
  static GoRoute _route(String path, GoRouterWidgetBuilder builder) => GoRoute(
    path: path,
    // A Builder, as go_router's own pages do, so the builder's context is
    // inside the route.
    pageBuilder: (_, state) =>
        _page(state, Builder(builder: (context) => builder(context, state))),
  );

  static Page<void> _page(GoRouterState state, Widget child) =>
      MaterialPage<void>(
        key: state.pageKey,
        name: state.name ?? state.path,
        arguments: {...state.pathParameters, ...state.uri.queryParameters},
        restorationId: state.pageKey.value,
        child: child,
      );

  static StatefulShellBranch _branch(
    String path,
    Widget view,
    GlobalKey<TabScrollState> top,
  ) => StatefulShellBranch(
    routes: [
      GoRoute(
        path: path,
        builder: (_, _) => TabScroll(key: top, child: view),
      ),
    ],
  );

  static Widget _player(BuildContext context, GoRouterState state) {
    final params = state.uri.queryParameters;
    final uri = params['uri'];
    if (uri == null || uri.isEmpty) return _notFound(context);
    return PlayerView(uri: uri, title: params['title'] ?? '');
  }

  static Widget _libraryPlaylist(BuildContext context, GoRouterState state) {
    final name = state.uri.queryParameters['name'];
    if (name == null || name.isEmpty) return _notFound(context);
    return LibraryPlaylistView(name: name);
  }

  static Widget _downloadsPlaylist(BuildContext context, GoRouterState state) {
    final id = state.pathParameters['id'];
    if (id == null || id.isEmpty) return _notFound(context);
    return PlaylistDetailView(id: id);
  }

  static Widget _playlist(BuildContext context, GoRouterState state) =>
      switch (state.extra) {
        final MediaInfo info => PlaylistView(info: info),
        _ => _notFound(context),
      };

  static Widget _notFound(BuildContext context) =>
      NotFoundView(onHome: () => context.go(AppRoutes.home));
}
