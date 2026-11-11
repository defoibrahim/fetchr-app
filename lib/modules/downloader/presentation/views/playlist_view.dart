import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/shared/domain/entities/quality.dart';
import '../../../../app/shared/download_prefs_provider.dart';
import '../../../../core/errors/result.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/scale.dart';
import '../../../../core/widgets/app_back_button.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../core/widgets/centered_content.dart';
import '../../../../core/widgets/segmented_pills.dart';
import '../../domain/entities/media_info.dart';
import '../../domain/entities/playlist_selection.dart';
import '../providers/home_notifier.dart';
import 'widgets/playlist_rows.dart';

const _metaGap = 6.0;
const _pillHeight = 44.0;
const _indexMinWidth = 18.0;
const _monoCharWidth = 7.0;

/// Pick the videos of a playlist and one quality for all of them. Pops the
/// number of downloads it started, or null when the user backs out.
class PlaylistView extends ConsumerStatefulWidget {
  const PlaylistView({super.key, required this.info});

  final MediaInfo info;

  @override
  ConsumerState<PlaylistView> createState() => _PlaylistViewState();
}

class _PlaylistViewState extends ConsumerState<PlaylistView> {
  // Native lists no cover for a playlist: it only makes sense for one item.
  late final List<Quality> _qualities = [
    for (final option in widget.info.options) option.quality,
  ];
  late Quality _quality;
  late PlaylistSelection _selection = PlaylistSelection.all(_total);
  bool _busy = false;

  int get _total => widget.info.entries.length;

  @override
  void initState() {
    super.initState();
    final preferred = ref.read(downloadPrefsProvider).quality;
    _quality = widget.info.pick(preferred).quality;
  }

  Future<void> _download() async {
    if (_busy) return;
    setState(() => _busy = true);
    final result = await ref
        .read(homeNotifierProvider.notifier)
        .downloadPlaylist(widget.info, _quality, _selection.indexes);
    if (!mounted) return;
    switch (result) {
      case Ok(:final value):
        Navigator.of(context).pop(value);
      case Err():
        setState(() => _busy = false);
        await AppSnackbar.showFailure(context, result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final type = context.type;
    final info = widget.info;
    final gutter = context.gutter;
    final folder = ref.watch(downloadPrefsProvider.select((p) => p.folder));
    final count = _selection.count;
    final indexWidth = math.max(
      _indexMinWidth,
      '$_total'.length * _monoCharWidth,
    );

    return Scaffold(
      bottomNavigationBar: PlaylistBottomBar(
        gutter: gutter,
        caption: 'Saves to ${_quality.savePath(folder)}',
        label: 'Download ${plural(count, 'video')}',
        onPressed: count == 0 || _busy ? null : _download,
      ),
      // One scroll view, so a short landscape window or a large text size
      // scrolls the header away instead of overflowing.
      body: SafeArea(
        bottom: false,
        child: CenteredContent(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        Gap.sm.w,
                        Gap.sm.h,
                        gutter,
                        Gap.xs.h,
                      ),
                      child: Row(
                        spacing: Gap.xs.w,
                        children: [
                          const AppBackButton(),
                          Text('Playlist', style: type.button),
                        ],
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(gutter, Gap.sm.h, gutter, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: _metaGap.h,
                        children: [
                          Text(
                            '${siteOf(info.url)} · ${plural(_total, 'video')}',
                            style: type.mono.copyWith(color: tokens.textMuted),
                            // A host reads left to right in any locale.
                            textDirection: TextDirection.ltr,
                          ),
                          Text(
                            info.title,
                            style: type.pageTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(gutter, Gap.lg.h, gutter, 0),
                      child: SegmentedPills<Quality>(
                        items: [for (final q in _qualities) (q, q.shortLabel)],
                        selected: _quality,
                        onChanged: (q) => setState(() => _quality = q),
                        height: _pillHeight,
                        trackRadius: Radii.row,
                        pillRadius: Radii.thumb,
                        mono: true,
                        trackColor: tokens.surface,
                        semanticLabel: 'Quality for all items',
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        gutter,
                        Gap.md.h,
                        gutter,
                        Gap.xs.h,
                      ),
                      child: SelectAllRow(
                        selection: _selection,
                        onTap: () =>
                            setState(() => _selection = _selection.toggleAll()),
                      ),
                    ),
                  ],
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: gutter),
                sliver: SliverList.builder(
                  itemCount: _total,
                  itemBuilder: (context, i) => PlaylistEntryRow(
                    number: i + 1,
                    numberWidth: indexWidth,
                    entry: info.entries[i],
                    ticked: _selection.isSelected(i),
                    onTap: () =>
                        setState(() => _selection = _selection.toggle(i)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
