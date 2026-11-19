import 'package:flutter/material.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/utils/scale.dart';
import '../../../../../core/widgets/confirm_dialog.dart';

/// For a link to a video inside a playlist: true for the whole playlist,
/// false for the video alone, null when the dialog is dismissed.
Future<bool?> showPlaylistChoice(BuildContext context) =>
    showDialog<bool>(context: context, builder: (_) => const _ChoiceDialog());

class _ChoiceDialog extends StatelessWidget {
  const _ChoiceDialog();

  @override
  Widget build(BuildContext context) {
    final dialog = DialogTheme.of(context);
    return Dialog(
      child: Padding(
        padding: EdgeInsets.all(Gap.xl.r),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Gap.lg.h,
          children: [
            Text('This video is in a playlist', style: dialog.titleTextStyle),
            Text(
              'Download just this video, or pick videos from the whole '
              'playlist?',
              style: dialog.contentTextStyle,
            ),
            Padding(
              padding: EdgeInsets.only(top: Gap.xs.h),
              child: DialogActions(
                cancelLabel: 'This video',
                cancelResult: false,
                confirmLabel: 'Playlist',
                onConfirm: () => Navigator.of(context).pop(true),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
