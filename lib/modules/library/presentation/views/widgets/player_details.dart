import 'package:flutter/material.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/theme_extensions.dart';
import '../../../../../core/utils/scale.dart';
import '../../../domain/entities/library_item.dart';
import 'player_info.dart';

const _titleTop = 18.0;
const _titleGap = 8.0;
const _actionsTop = 18.0;
const _infoTop = 22.0;

/// What goes with the picture, under it on a phone and beside it from 840 dp:
/// the title, where the file came from, Share and Delete, and the info card.
class PlayerDetails extends StatelessWidget {
  const PlayerDetails({
    super.key,
    required this.title,
    required this.source,
    required this.item,
    required this.onShare,
    required this.onDelete,
  });

  final String title;
  final String? source;

  /// Null for a file the library does not list: it gets neither the actions
  /// nor the info card, which both need the item.
  final LibraryItem? item;
  final ValueChanged<LibraryItem> onShare;
  final ValueChanged<LibraryItem> onDelete;

  @override
  Widget build(BuildContext context) {
    final type = context.type;
    final item = this.item;
    final source = this.source;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            context.gutter,
            _titleTop.h,
            context.gutter,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: _titleGap.h,
            children: [
              if (title.isNotEmpty)
                Text(
                  title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: type.mediaTitle,
                ),
              if (source != null)
                Text(
                  source,
                  style: type.mono.copyWith(color: context.tokens.textMuted),
                  // A host reads left to right in any locale.
                  textDirection: TextDirection.ltr,
                ),
            ],
          ),
        ),
        if (item != null) ...[
          Padding(
            padding: EdgeInsets.fromLTRB(
              context.gutter,
              _actionsTop.h,
              context.gutter,
              0,
            ),
            child: PlayerActions(
              onShare: () => onShare(item),
              onDelete: () => onDelete(item),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              context.gutter,
              _infoTop.h,
              context.gutter,
              Gap.lg.h,
            ),
            child: PlayerInfoList(item: item),
          ),
        ],
      ],
    );
  }
}
