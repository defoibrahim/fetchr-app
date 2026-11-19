import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes/app_routes.dart';
import '../../../../core/errors/result.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/theme_extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/scale.dart';
import '../../../../core/widgets/action_menu.dart';
import '../../../../core/widgets/app_back_button.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../core/widgets/centered_content.dart';
import '../../../../core/widgets/media_thumb.dart';
import '../../domain/entities/library_item.dart';
import '../../domain/extensions/library_item_extensions.dart';
import '../formatters/library_item_formatter.dart';
import '../providers/library_notifier.dart';
import '../providers/library_thumbnail_provider.dart';
import 'widgets/delete_library_item.dart';

const _thumbWidth = 96.0;
const _thumbAspect = 16 / 10;
const _numberWidth = 24.0;
const _metaGap = 6.0;
const _textGap = 3.0;
const _rowPadY = 7.0;

/// The saved files of one playlist, in playlist order.
class LibraryPlaylistView extends ConsumerStatefulWidget {
  const LibraryPlaylistView({super.key, required this.name});

  final String name;

  @override
  ConsumerState<LibraryPlaylistView> createState() =>
      _LibraryPlaylistViewState();
}

class _LibraryPlaylistViewState extends ConsumerState<LibraryPlaylistView> {
  bool _left = false;

  LibraryNotifier get _notifier => ref.read(libraryNotifierProvider.notifier);

  // Its last file is gone: there is nothing left to show here.
  void _leave() {
    if (_left) return;
    _left = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && context.canPop()) context.pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final type = context.type;
    final gutter = context.gutter;
    final name = widget.name;
    final library = ref.watch(libraryNotifierProvider);
    final items = (library.value ?? const <LibraryItem>[]).inPlaylist(name);
    if (library is AsyncData && items.isEmpty) _leave();

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CenteredContent(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const AppBackHeader('Library'),
                    Padding(
                      padding: EdgeInsets.fromLTRB(gutter, Gap.sm.h, gutter, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: _metaGap.h,
                        children: [
                          Text(
                            'Playlist · ${items.filesLine}',
                            style: type.mono.copyWith(color: tokens.textMuted),
                          ),
                          Text(
                            name,
                            style: type.pageTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    if (items.isNotEmpty)
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          gutter,
                          Gap.lg.h,
                          gutter,
                          Gap.sm.h,
                        ),
                        child: Row(
                          spacing: Gap.sm.w,
                          children: [
                            Expanded(
                              child: AppButton(
                                label: 'Show in folder',
                                variant: AppButtonVariant.outlined,
                                size: AppButtonSize.medium,
                                onPressed: () => _openFolder(items.first),
                              ),
                            ),
                            Expanded(
                              child: AppButton(
                                label: 'Delete playlist',
                                variant: AppButtonVariant.destructive,
                                size: AppButtonSize.medium,
                                onPressed: () => unawaited(
                                  deleteLibraryPlaylist(
                                    context,
                                    ref,
                                    name,
                                    items,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(gutter, 0, gutter, Gap.lg.h),
                sliver: SliverList.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return _Row(
                      key: ValueKey(item.uri),
                      item: item,
                      onPlay: () => _play(item),
                      onShare: () => _run(_notifier.share(item)),
                      onOpenFolder: () => _openFolder(item),
                      onDelete: () =>
                          unawaited(deleteLibraryItem(context, ref, item)),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _run(Future<Result<void>> action) =>
      unawaited(AppSnackbar.showFailure(context, action));

  void _openFolder(LibraryItem item) => _run(_notifier.openFolder(item));

  void _play(LibraryItem item) => unawaited(
    context.push(
      AppRoutes.playerLocation(uri: item.uri, title: item.nameInPlaylist),
    ),
  );
}

class _Row extends ConsumerWidget {
  const _Row({
    super.key,
    required this.item,
    required this.onPlay,
    required this.onShare,
    required this.onOpenFolder,
    required this.onDelete,
  });

  final LibraryItem item;
  final VoidCallback onPlay;
  final VoidCallback onShare;
  final VoidCallback onOpenFolder;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final type = context.type;
    final path = item.isAudio
        ? null
        : ref.watch(libraryThumbnailProvider(item.uri)).value;
    final seconds = (item.durationMs ?? 0) ~/ 1000;
    return ActionMenu(
      items: [
        ActionMenuItem.play(onPlay),
        ActionMenuItem.share(onShare),
        ActionMenuItem.showInFolder(onOpenFolder),
        ActionMenuItem.deleteFile(onDelete),
      ],
      builder: (context, controller) => InkWell(
        onTap: onPlay,
        onLongPress: controller.open,
        borderRadius: BorderRadius.circular(Radii.row.r),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: _rowPadY.h),
          child: Row(
            spacing: Gap.md.w,
            children: [
              SizedBox(
                width: _numberWidth.w,
                child: Text(
                  item.playlistNumber ?? '',
                  textAlign: TextAlign.end,
                  style: type.monoSmall.copyWith(color: tokens.textMuted),
                ),
              ),
              MediaThumb(
                image: path == null ? null : FileImage(File(path)),
                width: _thumbWidth.w,
                aspectRatio: _thumbAspect,
                duration: seconds > 0 ? formatDuration(seconds) : null,
                isAudio: item.isAudio,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  spacing: _textGap.h,
                  children: [
                    Text(
                      item.nameInPlaylist,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: type.body.copyWith(fontWeight: FontWeight.w500),
                    ),
                    Text(
                      item.metaText,
                      textDirection: TextDirection.ltr,
                      style: type.monoSmall.copyWith(color: tokens.textMuted),
                    ),
                  ],
                ),
              ),
              MoreActionsDots(controller: controller),
            ],
          ),
        ),
      ),
    );
  }
}
