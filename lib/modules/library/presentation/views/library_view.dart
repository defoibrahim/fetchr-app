import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes/app_routes.dart';
import '../../../../app/shared/domain/entities/quality.dart';
import '../../../../app/shared/download_prefs_provider.dart';
import '../../../../core/errors/failure_mapper.dart';
import '../../../../core/gen/assets.gen.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/theme_extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/scale.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../core/widgets/empty_view.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../../core/widgets/loading_view.dart';
import '../../../../core/widgets/section_header.dart';
import '../../domain/entities/library_item.dart';
import '../providers/library_notifier.dart';
import 'widgets/delete_library_item.dart';
import 'widgets/library_card.dart';

const _columnGap = 12.0;
const _rowGap = 18.0;
const _headerGap = 6.0;
const _filterTop = 14.0;
const _filterBottom = 10.0;
const _gridTop = 4.0;

enum _Filter {
  all('All', 'No files yet'),
  video('Video', 'No video files'),
  audio('Audio', 'No audio files');

  const _Filter(this.label, this.emptyText);

  final String label;
  final String emptyText;

  bool matches(LibraryItem item) => switch (this) {
    all => true,
    video => !item.isAudio,
    audio => item.isAudio,
  };
}

class LibraryView extends ConsumerStatefulWidget {
  const LibraryView({super.key});

  @override
  ConsumerState<LibraryView> createState() => _LibraryViewState();
}

class _LibraryViewState extends ConsumerState<LibraryView> {
  bool? _visible;
  var _filter = _Filter.all;

  // The shell keeps a hidden tab mounted with its tickers off, so files
  // downloaded meanwhile only show up after a reload when the tab is shown
  // again. Null until the first build, which must not reload.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.valuesOf(context).enabled;
    final shown = _visible == false && visible;
    _visible = visible;
    if (!shown) return;
    // Riverpod cannot schedule a refresh while the tree builds.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(libraryNotifierProvider.notifier).refresh());
    });
  }

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(libraryNotifierProvider);
    final folder = ref.watch(downloadPrefsProvider.select((p) => p.folder));
    final count = switch (library) {
      AsyncData(:final value) => value.length,
      _ => null,
    };
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(folder: folder, count: count),
            _Filters(
              selected: _filter,
              onChanged: (filter) => setState(() => _filter = filter),
            ),
            Expanded(
              child: switch (library) {
                AsyncData(:final value) => _content(value, folder),
                // A retry reloads from the error state: keep showing loading,
                // not the old error, until it lands.
                AsyncError(:final error) when !library.isLoading => ErrorView(
                  message: messageOf(error),
                  onRetry: () => ref.invalidate(libraryNotifierProvider),
                ),
                _ => const LoadingView(),
              },
            ),
          ],
        ),
      ),
    );
  }

  // One scroll view for the grid and both empty states, so every one of them
  // pulls to refresh.
  Widget _content(List<LibraryItem> items, String folder) {
    final shown = [
      for (final item in items)
        if (_filter.matches(item)) item,
    ];
    // The window decides, not the grid's width: beside the rail a 900 dp
    // window leaves the grid under 840.
    final columns = switch (context.windowClass) {
      WindowClass.expanded => 4,
      WindowClass.medium => 3,
      _ => 2,
    };
    return RefreshIndicator(
      onRefresh: ref.read(libraryNotifierProvider.notifier).refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (shown.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: items.isEmpty ? _emptyLibrary(folder) : _emptyFilter(),
            )
          else
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                context.gutter,
                _gridTop.h,
                context.gutter,
                Gap.lg.h,
              ),
              sliver: SliverLayoutBuilder(
                builder: (context, constraints) {
                  final gap = _columnGap.w;
                  final width =
                      (constraints.crossAxisExtent - gap * (columns - 1)) /
                      columns;
                  return SliverGrid.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: gap,
                      mainAxisSpacing: _rowGap.h,
                      mainAxisExtent: LibraryCard.heightFor(context, width),
                    ),
                    itemCount: shown.length,
                    itemBuilder: (_, index) => _card(shown[index]),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _card(LibraryItem item) => LibraryCard(
    key: ValueKey(item.uri),
    item: item,
    onPlay: () => _play(item),
    onShare: () => _share(item),
    onOpenFolder: () => _openFolder(item),
    onDelete: () => unawaited(deleteLibraryItem(context, ref, item)),
  );

  Widget _emptyLibrary(String folder) => EmptyView(
    illustration: Assets.icons.emptyLibrary,
    title: _Filter.all.emptyText,
    message:
        'Finished videos and audio are saved to '
        '${Quality.best.savePath(folder)} and ${Quality.mp3.savePath(folder)} '
        'and show up here and in Gallery.',
    action: AppButton(
      label: 'Paste a link',
      size: AppButtonSize.medium,
      expanded: false,
      onPressed: () => context.go(AppRoutes.home),
    ),
  );

  Widget _emptyFilter() => Center(
    child: Text(
      _filter.emptyText,
      style: context.type.body.copyWith(color: context.tokens.textMuted),
    ),
  );

  void _play(LibraryItem item) {
    unawaited(
      context.push(AppRoutes.playerLocation(uri: item.uri, title: item.name)),
    );
  }

  Future<void> _share(LibraryItem item) async {
    await AppSnackbar.showFailure(
      context,
      ref.read(libraryNotifierProvider.notifier).share(item),
    );
  }

  Future<void> _openFolder(LibraryItem item) async {
    await AppSnackbar.showFailure(
      context,
      ref.read(libraryNotifierProvider.notifier).openFolder(item),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.folder, required this.count});

  final String folder;

  /// Null until the library has loaded, so no count flashes in as 0.
  final int? count;

  @override
  Widget build(BuildContext context) {
    final type = context.type;
    final n = count;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        context.gutter,
        Gap.sm.h,
        context.gutter,
        Gap.xs.h,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: _headerGap.h,
        children: [
          const ScreenTitle('Library'),
          if (n != null)
            Text(
              '$folder · ${plural(n, 'file')}',
              textDirection: TextDirection.ltr,
              style: type.mono.copyWith(color: context.tokens.textMuted),
            ),
        ],
      ),
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({required this.selected, required this.onChanged});

  final _Filter selected;
  final ValueChanged<_Filter> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        context.gutter,
        _filterTop.h,
        context.gutter,
        _filterBottom.h,
      ),
      child: Wrap(
        spacing: Gap.sm.w,
        runSpacing: Gap.sm.h,
        children: [
          for (final filter in _Filter.values)
            ChoiceChip(
              label: Text(filter.label),
              selected: filter == selected,
              onSelected: (_) => onChanged(filter),
            ),
        ],
      ),
    );
  }
}
