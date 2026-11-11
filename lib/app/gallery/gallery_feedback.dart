import 'package:flutter/material.dart';

import '../../core/gen/assets.gen.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/theme_extensions.dart';
import '../../core/utils/scale.dart';
import '../../core/utils/widget_utils.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_snackbar.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/widgets/error_card.dart';
import 'gallery_section.dart';

class ErrorCardsSection extends StatelessWidget {
  const ErrorCardsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return GallerySection(
      title: 'Error cards',
      children: [
        GalleryExample(
          label: 'full',
          child: ErrorCard(
            data: ErrorCardData(
              icon: Assets.icons.wifiOff,
              title: 'No internet connection',
              body: [
                const TextSpan(text: 'Connect to a network and try '),
                AppTextStyles.monoSpan('yt-dlp'),
                const TextSpan(text: ' again.'),
              ],
              actions: const [
                ErrorCardAction(label: 'Try again', onPressed: noop),
                ErrorCardAction(label: 'Dismiss', onPressed: noop),
              ],
            ),
          ),
        ),
        GalleryExample(
          label: 'full, busy action',
          child: ErrorCard(
            data: ErrorCardData(
              icon: Assets.icons.alertCircle,
              title: 'This site needs an update',
              body: const [TextSpan(text: 'Update yt-dlp, then try again.')],
              actions: const [
                ErrorCardAction(
                  label: 'Update yt-dlp',
                  onPressed: noop,
                  primary: true,
                  busy: true,
                  busyLabel: 'Updating…',
                ),
              ],
            ),
          ),
        ),
        GalleryExample(
          label: 'compact',
          child: ErrorCard(
            layout: ErrorCardLayout.compact,
            data: ErrorCardData(
              icon: Assets.icons.alertCircle,
              title: 'Video 12',
              body: const [TextSpan(text: 'Connection lost')],
              actions: const [ErrorCardAction(label: 'Retry', onPressed: noop)],
            ),
          ),
        ),
      ],
    );
  }
}

class OverlaysSection extends StatelessWidget {
  const OverlaysSection({super.key});

  @override
  Widget build(BuildContext context) {
    Widget open(String label, VoidCallback onPressed) => AppButton(
      label: label,
      onPressed: onPressed,
      variant: AppButtonVariant.outlined,
      size: AppButtonSize.small,
      expanded: false,
    );

    return GallerySection(
      title: 'Dialog, sheet and snackbars',
      children: [
        Wrap(
          spacing: Gap.sm.w,
          runSpacing: Gap.sm.h,
          children: [
            open(
              'Confirm dialog',
              () => showConfirmDialog(
                context,
                title: 'Delete this file?',
                message: 'It will be deleted from your device.',
                confirmLabel: 'Delete',
                icon: Assets.icons.trash,
                meta: ('Movies/Fetchr', '96 MB'),
              ),
            ),
            open(
              'Bottom sheet',
              () =>
                  showAppBottomSheet<void>(context, child: const _SheetBody()),
            ),
            open(
              'Info snackbar',
              () => AppSnackbar.show(context, 'Link copied'),
            ),
            open(
              'Success snackbar',
              () => AppSnackbar.show(
                context,
                'Saved to Movies/Fetchr',
                type: SnackType.success,
              ),
            ),
            open(
              'Error snackbar',
              () => AppSnackbar.show(
                context,
                'Could not save the file',
                type: SnackType.error,
              ),
            ),
            open(
              'Snackbar with an action',
              () => AppSnackbar.show(
                context,
                'Download paused',
                action: ('Resume', noop),
              ),
            ),
            open(
              'Undo snackbar',
              () => AppSnackbar.showUndo(context, 'File deleted'),
            ),
          ],
        ),
      ],
    );
  }
}

class _SheetBody extends StatelessWidget {
  const _SheetBody();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Gap.gutter.w,
        Gap.sm.h,
        Gap.gutter.w,
        Gap.xl.h,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: Gap.sm.h,
        children: [
          Text('Sheet title', style: context.type.sheetTitle),
          Text(
            'The grabber, the scrim and the corners come from '
            'showAppBottomSheet.',
            style: context.type.body.copyWith(color: context.tokens.textMuted),
          ),
        ],
      ),
    );
  }
}
