import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes/app_routes.dart';
import '../../../../core/errors/result.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/scale.dart';
import '../../../../core/widgets/app_back_button.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../core/widgets/centered_content.dart';
import '../../../../core/widgets/loading_view.dart';
import '../../../../core/widgets/undoable_delete.dart';
import '../../domain/entities/playlist_download.dart';
import '../providers/downloads_notifier.dart';
import '../providers/playlist_download_provider.dart';
import 'widgets/playlist_detail_parts.dart';

/// One playlist download: the video on its way, every video as a tile, the
/// queue to reorder, and Stop or Pause for all of it.
class PlaylistDetailView extends ConsumerStatefulWidget {
  const PlaylistDetailView({super.key, required this.id});

  final String id;

  @override
  ConsumerState<PlaylistDetailView> createState() => _PlaylistDetailState();
}

class _PlaylistDetailState extends ConsumerState<PlaylistDetailView> {
  String? _selectedId;
  bool _leaving = false;

  // Read per tap: the notifier lives with the Downloads tab, so an Undo still
  // lands after this screen is gone.
  DownloadsNotifier get _notifier =>
      ref.read(downloadsNotifierProvider.notifier);

  @override
  Widget build(BuildContext context) {
    // Nothing left to finish, or stopped: back to the list.
    ref.listen(playlistDownloadProvider(widget.id), (previous, next) {
      if (previous != null && next == null) _leave();
    });
    final playlist = ref.watch(playlistDownloadProvider(widget.id));
    final gutter = context.gutter;
    return Scaffold(
      bottomNavigationBar: playlist == null
          ? null
          : PlaylistBar(
              paused: playlist.isPaused,
              onStop: () => unawaited(_stop()),
              onPauseAll: () => _run(_notifier.pausePlaylist(widget.id)),
              onResumeAll: () => _run(_notifier.resumePlaylist(widget.id)),
            ),
      body: SafeArea(
        bottom: false,
        child: CenteredContent(
          child: playlist == null
              ? const LoadingView()
              : _body(playlist, gutter),
        ),
      ),
    );
  }

  Widget _body(PlaylistDownload playlist, double gutter) {
    final type = context.type;
    final tokens = context.tokens;
    final current = playlist.current;
    final upNext = playlist.upNext;
    final selected =
        playlist.items.where((i) => i.id == _selectedId).firstOrNull ?? current;
    final padded = EdgeInsets.symmetric(horizontal: gutter);
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: AppBackHeader(playlist.title)),
        if (current != null)
          SliverPadding(
            padding: padded.copyWith(top: Gap.xs.h, bottom: Gap.lg.h),
            sliver: SliverToBoxAdapter(child: CurrentItem(item: current)),
          ),
        SliverPadding(
          padding: padded,
          sliver: SliverToBoxAdapter(
            child: TilePanel(
              playlist: playlist,
              selected: selected,
              onSelect: (item) => setState(() => _selectedId = item.id),
              onAction: (item, action) => _act(playlist, item, action),
            ),
          ),
        ),
        if (upNext.isNotEmpty)
          SliverPadding(
            padding: padded.copyWith(top: Gap.xl.h, bottom: Gap.xs.h),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  Expanded(child: Text('Up next', style: type.section)),
                  if (!playlist.isPaused)
                    Text(
                      'Drag to reorder',
                      style: type.caption.copyWith(color: tokens.textMuted),
                    ),
                ],
              ),
            ),
          ),
        SliverPadding(
          padding: padded.copyWith(bottom: Gap.xl.h),
          sliver: SliverReorderableList(
            itemCount: upNext.length,
            onReorderItem: (from, to) {
              if (from == to) return;
              final order = [for (final item in upNext) item.id];
              order.insert(to, order.removeAt(from));
              _run(_notifier.reorderQueue(order));
            },
            itemBuilder: (_, index) => UpNextRow(
              key: ValueKey(upNext[index].id),
              item: upNext[index],
              index: index,
              // Paused videos have no place in the queue to move.
              draggable: !playlist.isPaused,
              onSkip: () => unawaited(_skip(playlist, upNext[index])),
            ),
          ),
        ),
      ],
    );
  }

  void _act(PlaylistDownload playlist, PlaylistItem item, TileAction action) {
    switch (action) {
      case TileAction.play:
        final uri = item.task.fileUri;
        if (uri == null) return;
        unawaited(
          context.push(AppRoutes.playerLocation(uri: uri, title: item.title)),
        );
      case TileAction.retry:
        _run(_notifier.retry(item.id));
      case TileAction.skip:
        unawaited(_skip(playlist, item));
      case TileAction.addBack:
        _run(_notifier.unskip(item.id));
    }
  }

  Future<void> _skip(PlaylistDownload playlist, PlaylistItem item) async {
    final notifier = _notifier;
    final messenger = Navigator.of(context, rootNavigator: true).context;
    final order = [for (final next in playlist.upNext) next.id];
    final result = await notifier.skip(item.id);
    if (!messenger.mounted) return;
    if (result is Err) return _run(result);
    if (await AppSnackbar.showUndo(messenger, 'Skipped “${item.title}”')) {
      if (messenger.mounted) {
        await AppSnackbar.showFailure(
          messenger,
          notifier.unskip(item.id, order: order),
        );
      }
    }
  }

  // Applied at once and undone on Undo; the videos left are dropped only when
  // the snackbar closes any other way.
  Future<void> _stop() async {
    final notifier = _notifier;
    final messenger = Navigator.of(context, rootNavigator: true).context;
    _leaving = true;
    final result = await notifier.stopPlaylist(widget.id);
    if (!messenger.mounted) return;
    switch (result) {
      case Err():
        _leaving = false;
        return _run(result);
      case Ok(value: final stop):
        await runUndoableDelete(
          messenger,
          message: 'Playlist stopped · ${plural(stop.kept, 'video')} kept',
          hide: () {
            if (mounted && context.canPop()) context.pop();
          },
          restore: () => unawaited(
            AppSnackbar.showFailure(messenger, notifier.undoStop(stop)),
          ),
          commit: () => notifier.commitStop(stop),
        );
    }
  }

  void _leave() {
    if (_leaving) return;
    _leaving = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && context.canPop()) context.pop();
    });
  }

  void _run(FutureOr<Result<Object?>> result) =>
      unawaited(AppSnackbar.showFailure(context, result));
}
