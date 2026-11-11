import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes/app_routes.dart';
import '../../../../app/shared/notification_permission_provider.dart';
import '../../../../core/errors/failure_mapper.dart';
import '../../../../core/errors/result.dart';
import '../../../../core/gen/assets.gen.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/scale.dart';
import '../../../../core/widgets/app_button.dart';
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
import '../../domain/extensions/download_task_extensions.dart';
import '../formatters/download_task_formatter.dart';
import '../formatters/quality_formatter.dart';
import '../providers/downloads_notifier.dart';
import 'widgets/attention_row.dart';
import 'widgets/done_row.dart';
import 'widgets/download_card.dart';
import 'widgets/notification_hint.dart';
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

class DownloadsView extends ConsumerStatefulWidget {
  const DownloadsView({super.key});

  @override
  ConsumerState<DownloadsView> createState() => _DownloadsViewState();
}

class _DownloadsViewState extends ConsumerState<DownloadsView> {
  bool _queueExpanded = false;

  // Read per tap: an autoDispose notifier captured in build can be gone by
  // the time the user taps.
  DownloadsNotifier get _notifier =>
      ref.read(downloadsNotifierProvider.notifier);

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(downloadsNotifierProvider);
    final groups = switch (tasks) {
      AsyncData(:final value) => value.groupedAt(DateTime.now()),
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
              Padding(
                padding: EdgeInsets.symmetric(horizontal: gutter),
                child: const NotificationHint(),
              ),
              Expanded(
                child: switch (tasks) {
                  AsyncData() when groups!.isEmpty => _empty(context),
                  AsyncData() => _list(context, groups!, gutter),
                  // A retry reloads from the error state: keep showing
                  // loading, not the old error, until it lands.
                  AsyncError(:final error) when !tasks.isLoading => ErrorView(
                    message: messageOf(error),
                    onRetry: () => ref.invalidate(downloadsNotifierProvider),
                  ),
                  _ => const LoadingView(),
                },
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

  Widget _list(BuildContext context, DownloadGroups groups, double gutter) {
    // Widgets are cheap; only the rows on screen get built.
    final items = <Widget>[];
    void group(String title, List<Widget> rows) {
      if (rows.isEmpty) return;
      items
        ..add(_overline(title, first: items.isEmpty))
        ..addAll(rows);
    }

    group('ACTIVE', [
      for (final task in groups.active) _card(task),
      if (groups.queued.isNotEmpty) _queue(groups.queued),
    ]);
    group('NEEDS ATTENTION', [
      for (final task in groups.attention) _attention(task),
    ]);
    group('DONE TODAY', [for (final task in groups.doneToday) _done(task)]);
    final indexOf = {
      for (final (index, item) in items.indexed) item.key: index,
    };
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(gutter, _listTop.h, gutter, _listBottom.h),
      itemCount: items.length,
      findItemIndexCallback: (key) => indexOf[key],
      itemBuilder: (_, index) => items[index],
      separatorBuilder: (_, _) => SizedBox(height: _rowGap.h),
    );
  }

  Widget _overline(String text, {required bool first}) =>
      _Overline(key: ValueKey('overline-$text'), text: text, first: first);

  Widget _card(DownloadTask task) => DownloadCard(
    key: ValueKey(task.id),
    task: task,
    onPause: () => _run(_notifier.pause(task.id)),
    onResume: () => _run(_notifier.resume(task.id)),
    onCancel: () => _run(_notifier.cancel(task.id)),
    onRestart: () => _run(_notifier.retry(task.id)),
    onRemove: () => _remove(task),
  );

  Widget _queue(List<DownloadTask> queued) => QueuedRows(
    key: const ValueKey('queue'),
    tasks: queued,
    expanded: _queueExpanded,
    onToggle: () => setState(() => _queueExpanded = !_queueExpanded),
    onCancel: (id) => _run(_notifier.cancel(id)),
  );

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
    final confirmed = await confirmDeleteFile(
      context,
      task.request.title,
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
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(top: (first ? _firstOverlineTop : _overlineTop).h),
    child: SectionOverline(text),
  );
}
