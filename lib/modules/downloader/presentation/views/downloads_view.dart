import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes/app_routes.dart';
import '../../../../app/shared/notification_permission_provider.dart';
import '../../../../app/shared/platform_traits_provider.dart';
import '../../../../core/errors/failure_mapper.dart';
import '../../../../core/errors/result.dart';
import '../../../../core/gen/assets.gen.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/haptics.dart';
import '../../../../core/utils/scale.dart';
import '../../../../core/widgets/app_animated_sliver_list.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_fade_switcher.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../core/widgets/centered_content.dart';
import '../../../../core/widgets/confirm_dialog.dart';
import '../../../../core/widgets/empty_view.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../../core/widgets/loading_view.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/undoable_delete.dart';
import '../../domain/entities/download_groups.dart';
import '../../domain/entities/download_task.dart';
import '../../domain/entities/playlist_download.dart';
import '../../domain/extensions/download_task_extensions.dart';
import '../formatters/download_task_formatter.dart';
import '../formatters/quality_formatter.dart';
import '../providers/downloads_notifier.dart';
import 'widgets/attention_row.dart';
import 'widgets/done_row.dart';
import 'widgets/download_card.dart';
import 'widgets/notification_hint.dart';
import 'widgets/playlist_card.dart';
import 'widgets/queued_rows.dart';

const _headerTop = 8.0;
const _headerBottom = 4.0;
const _dot = 8.0;
const _subtitleSize = 13.0;
const _listTop = 12.0;
const _listBottom = 16.0;
const _rowGap = 10.0;
const _firstOverlineTop = 4.0;
const _overlineTop = 8.0;

/// How long a finished card stays in Active, full and "Saved", before its
/// Done row takes over.
const savedHold = Duration(milliseconds: 400);

enum _Kind { overline, playlist, active, queue, attention, done }

/// A row of the list: its kind and the task, playlist or title it shows. A
/// task that changes group changes key, so it leaves one group and arrives in
/// the other.
typedef _Row = (_Kind, String);

/// A finished task's last Active snapshot, shown until [controller] ends.
class _Hold {
  _Hold(this.task, this.controller);

  final DownloadTask task;
  final AnimationController controller;
}

class DownloadsView extends ConsumerStatefulWidget {
  const DownloadsView({super.key});

  @override
  ConsumerState<DownloadsView> createState() => _DownloadsViewState();
}

class _DownloadsViewState extends ConsumerState<DownloadsView>
    with TickerProviderStateMixin {
  bool _queueExpanded = false;

  // The Active cards of the last build, held ones aside: a task that was
  // among them and has finished holds its card a moment.
  var _lastActive = <String, DownloadTask>{};
  final _holds = <String, _Hold>{};

  // Done rows seen so far (the first build's count as seen), and the ones
  // new in this frame, whose check pops.
  Set<String>? _seenDone;
  final _newDone = <String>{};

  // When the tab last came into view. A download that finished before then
  // finished out of sight: it neither holds nor pops, even though the first
  // builds back can still show its old Active snapshot.
  DateTime? _visibleSince;
  var _visible = false;

  bool _finishedInView(DownloadTask task) {
    final since = _visibleSince;
    final at = task.finishedAt;
    return _visible && since != null && (at == null || !at.isBefore(since));
  }

  // Read per tap: an autoDispose notifier captured in build can be gone by
  // the time the user taps.
  DownloadsNotifier get _notifier =>
      ref.read(downloadsNotifierProvider.notifier);

  @override
  void dispose() {
    for (final hold in _holds.values) {
      hold.controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(downloadsNotifierProvider);
    final groups = switch (tasks) {
      AsyncData(:final value) => _holding(
        value,
        value.groupedAt(DateTime.now()),
      ),
      _ => null,
    };
    final gutter = context.gutter;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CenteredContent(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(
                gutter: gutter,
                running: groups != null && !groups.isEmpty,
              ),
              // Asking spends iOS's one prompt, and nothing posts there yet.
              if (ref.watch(platformTraitsProvider).asksNotificationPermission)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: gutter),
                  child: const NotificationHint(),
                ),
              Expanded(
                // Cross-fades by kind; a snapshot of the same kind repaints
                // in place.
                child: AppFadeSwitcher(
                  child: switch (tasks) {
                    AsyncData() when groups!.isEmpty => KeyedSubtree(
                      key: const ValueKey('empty'),
                      child: _empty(context),
                    ),
                    AsyncData() => KeyedSubtree(
                      key: const ValueKey('list'),
                      child: _list(context, groups!, gutter),
                    ),
                    // A retry reloads from the error state: keep showing
                    // loading, not the old error, until it lands.
                    AsyncError(:final error) when !tasks.isLoading => ErrorView(
                      key: const ValueKey('error'),
                      message: messageOf(error),
                      onRetry: () => ref.invalidate(downloadsNotifierProvider),
                    ),
                    _ => const LoadingView(key: ValueKey('loading')),
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _empty(BuildContext context) => EmptyView(
    illustration: Assets.icons.emptyDownloads,
    title: 'Nothing downloading',
    message:
        'Active, queued and failed downloads appear here, even after you close the app.',
    action: AppButton(
      label: 'Paste a link',
      variant: AppButtonVariant.outlined,
      size: AppButtonSize.medium,
      expanded: false,
      onPressed: () => context.go(AppRoutes.home),
    ),
  );

  /// [groups] with each task that has just finished from Active kept in
  /// Active, at its place, for [savedHold]. Not under reduce motion, nor while
  /// the tab is hidden, where nobody would see it.
  DownloadGroups _holding(List<DownloadTask> tasks, DownloadGroups groups) {
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible && !_visible) _visibleSince = DateTime.now();
    _visible = visible;
    final canHold = !context.reduceMotion && visible;
    final last = _lastActive;
    // Hidden, the snapshot is forgotten: a task that finishes out of sight
    // arrives in Done without a hold when the tab is shown again.
    _lastActive = canHold
        ? {for (final task in groups.active) task.id: task}
        : <String, DownloadTask>{};
    // A hold still running when the tab is hidden (or reduce motion is turned
    // on) ends now, not in a burst when the tab comes back.
    if (!canHold && _holds.isNotEmpty) {
      for (final MapEntry(:key, :value) in _holds.entries) {
        value.controller.dispose();
        _seenDone?.add(key);
      }
      _holds.clear();
    }
    for (final task in tasks) {
      if (task.status != TaskStatus.completed) continue;
      final shown = last[task.id];
      if (shown == null || !canHold || _holds.containsKey(task.id)) continue;
      // Only a live card that finished in view holds. A pause or cancel shown
      // ahead of native that lost the race to the finish goes straight to
      // Done, and so does a download that finished out of sight.
      final live = shown.status == TaskStatus.running;
      if (live && _finishedInView(task)) _hold(shown);
    }
    if (_holds.isEmpty) return groups;
    final active = {for (final task in groups.active) task.id};
    final held = {
      for (final MapEntry(:key, :value) in _holds.entries) key: value.task,
    };
    return DownloadGroups(
      playlists: groups.playlists,
      // The tasks keep native's order, so a held card stays where it was.
      active: [
        for (final task in tasks)
          if (active.contains(task.id)) task else ?held[task.id],
      ],
      queued: groups.queued,
      attention: groups.attention,
      doneToday: [
        for (final task in groups.doneToday)
          if (!held.containsKey(task.id)) task,
      ],
    );
  }

  void _hold(DownloadTask shown) {
    final controller = AnimationController(vsync: this, duration: savedHold);
    _holds[shown.id] = _Hold(shown, controller);
    // A future that completes with the run, not a Timer: pumpAndSettle waits
    // for it, and dispose stops it.
    controller.forward().then((_) {
      if (!mounted) return;
      setState(() => _holds.remove(shown.id));
      controller.dispose();
    });
  }

  Widget _list(BuildContext context, DownloadGroups groups, double gutter) {
    final rows = <_Row>[];
    void group(String title, List<_Row> items) {
      if (items.isEmpty) return;
      rows
        ..add((_Kind.overline, title))
        ..addAll(items);
    }

    group('ACTIVE', [
      for (final playlist in groups.playlists) (_Kind.playlist, playlist.id),
      for (final task in groups.active) (_Kind.active, task.id),
      if (groups.queued.isNotEmpty) (_Kind.queue, ''),
    ]);
    group('NEEDS ATTENTION', [
      for (final task in groups.attention) (_Kind.attention, task.id),
    ]);
    group('DONE TODAY', [
      for (final task in groups.doneToday) (_Kind.done, task.id),
    ]);
    _markNewDone(groups.doneToday);
    final playlists = {
      for (final playlist in groups.playlists) playlist.id: playlist,
    };
    final tasks = {
      for (final task in [
        ...groups.active,
        ...groups.attention,
        ...groups.doneToday,
      ])
        task.id: task,
    };
    final first = rows.first;
    return CustomScrollView(
      slivers: [
        SliverPadding(
          // Each row carries the gap below it, so the gap folds with the row.
          padding: EdgeInsets.fromLTRB(
            gutter,
            _listTop.h,
            gutter,
            (_listBottom - _rowGap).h,
          ),
          sliver: AppAnimatedSliverList<_Row>(
            keys: rows,
            itemBuilder: (context, row) => Padding(
              padding: EdgeInsets.only(bottom: _rowGap.h),
              child: _row(row, first: row == first, playlists, tasks, groups),
            ),
          ),
        ),
      ],
    );
  }

  // The first build's rows count as seen; a later new one pops its check in
  // the frame it arrives, and only in that frame.
  void _markNewDone(List<DownloadTask> done) {
    final seen = _seenDone;
    if (seen == null) {
      _seenDone = {for (final task in done) task.id};
      return;
    }
    // A row that arrives for a download finished out of sight is seen, not new.
    final fresh = [
      for (final task in done)
        if (seen.add(task.id) && _finishedInView(task)) task.id,
    ];
    if (fresh.isEmpty) return;
    _newDone.addAll(fresh);
    WidgetsBinding.instance.addPostFrameCallback((_) => _newDone.clear());
  }

  Widget _row(
    _Row row,
    Map<String, PlaylistDownload> playlists,
    Map<String, DownloadTask> tasks,
    DownloadGroups groups, {
    required bool first,
  }) {
    final (kind, id) = row;
    return switch (kind) {
      _Kind.overline => _overline(id, first: first),
      _Kind.playlist => _playlist(playlists[id]!),
      _Kind.active => _card(tasks[id]!),
      _Kind.queue => _queue(groups.queued),
      _Kind.attention => _attention(tasks[id]!),
      _Kind.done => _done(tasks[id]!),
    };
  }

  Widget _playlist(PlaylistDownload playlist) => PlaylistCard(
    key: ValueKey('playlist-${playlist.id}'),
    playlist: playlist,
    onOpen: () => unawaited(
      context.push(AppRoutes.downloadsPlaylistLocation(playlist.id)),
    ),
    onPauseAll: () => _run(_notifier.pausePlaylist(playlist.id)),
    onResumeAll: () => _run(_notifier.resumePlaylist(playlist.id)),
  );

  Widget _overline(String text, {required bool first}) =>
      _Overline(key: ValueKey('overline-$text'), text: text, first: first);

  Widget _card(DownloadTask task) => DownloadCard(
    key: ValueKey(task.id),
    task: task,
    // The state rebuilds this whenever a pending pause or cancel changes.
    settling: _notifier.isSettling(task.id),
    saved: _holds.containsKey(task.id),
    onPause: () => _run(_notifier.pause(task.id)),
    onResume: () => _run(_notifier.resume(task.id)),
    onCancel: () => _cancel(task.id),
    onRestart: () => _run(_notifier.retry(task.id)),
    onRemove: () => _remove(task),
  );

  Widget _queue(List<DownloadTask> queued) => QueuedRows(
    key: const ValueKey('queue'),
    tasks: queued,
    expanded: _queueExpanded,
    onToggle: () => setState(() => _queueExpanded = !_queueExpanded),
    onCancel: _cancel,
  );

  void _cancel(String id) {
    AppHaptics.warn();
    _run(_notifier.cancel(id));
  }

  Widget _attention(DownloadTask task) => AttentionRow(
    key: ValueKey(task.id),
    task: task,
    onRetry: () => _run(_notifier.retry(task.id)),
    onOpenSettings: () =>
        unawaited(ref.read(notificationPermissionProvider).openSettings()),
    onRemove: () => _remove(task),
  );

  Widget _done(DownloadTask task) => DoneRow(
    key: ValueKey(task.id),
    task: task,
    popCheck: _newDone.contains(task.id),
    onPlay: () => _play(task),
    onShowInFolder: () => _showInFolder(task),
    onDelete: () => unawaited(_deleteFile(task)),
  );

  void _run(Future<Result<void>> result) =>
      unawaited(AppSnackbar.showFailure(context, result));

  void _play(DownloadTask task) {
    final uri = task.fileUri;
    if (uri == null) return;
    unawaited(
      context.push(
        AppRoutes.playerLocation(uri: uri, title: task.request.title),
      ),
    );
  }

  void _showInFolder(DownloadTask task) {
    final uri = task.fileUri;
    if (uri != null) _run(_notifier.openFolder(uri));
  }

  Future<void> _deleteFile(DownloadTask task) async {
    final size = task.fileSize;
    final traits = ref.read(platformTraitsProvider);
    final confirmed = await confirmDeleteFile(
      context,
      task.request.title,
      deviceWord: traits.deviceWord,
      galleryWord: traits.galleryWord,
      meta: size == null || size <= 0
          ? null
          : (task.request.quality.formatLabel, formatBytes(size)),
    );
    if (!confirmed || !mounted) return;
    await _remove(task, message: 'Deleted');
  }

  // The notifier is read before anything hides the row: hiding unmounts it,
  // and a task nobody watches any more cannot be removed.
  Future<void> _remove(DownloadTask task, {String message = 'Removed'}) {
    final notifier = _notifier;
    return runUndoableDelete(
      context,
      message: message,
      hide: () => notifier.hide(task.id),
      restore: () => notifier.unhide(task.id),
      commit: () => notifier.remove(task.id),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.gutter, required this.running});

  final double gutter;
  final bool running;

  @override
  Widget build(BuildContext context) {
    final type = context.type;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        gutter,
        _headerTop.h,
        gutter,
        _headerBottom.h,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: _rowGap.h,
        children: [
          const ScreenTitle('Downloads'),
          if (running)
            Row(
              spacing: Gap.sm.w,
              children: [
                Container(
                  width: _dot.r,
                  height: _dot.r,
                  decoration: BoxDecoration(
                    // The accent in dark, the ink in light.
                    color: context.colors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                Flexible(
                  child: Text(
                    'Keeps running when you close the app',
                    style: type.caption.copyWith(
                      fontSize: _subtitleSize,
                      color: context.tokens.textMuted,
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

class _Overline extends StatelessWidget {
  const _Overline({super.key, required this.text, required this.first});

  final String text;
  final bool first;

  @override
  Widget build(BuildContext context) => AnimatedPadding(
    // A heading that becomes the first one, or stops being it, moves with
    // the rows leaving or arriving above it.
    duration: context.motion(Motion.emphasis),
    curve: Motion.standard,
    padding: EdgeInsets.only(top: (first ? _firstOverlineTop : _overlineTop).h),
    child: SectionOverline(text),
  );
}
