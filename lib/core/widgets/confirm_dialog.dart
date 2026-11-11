import 'package:flutter/material.dart';

import '../gen/assets.gen.dart';
import '../theme/app_spacing.dart';
import '../theme/theme_extensions.dart';
import '../utils/scale.dart';
import 'app_button.dart';
import 'error_icon_tile.dart';

const _iconSize = 22.0;
const _metaPadY = 10.0;
const _buttonGap = 10.0;

/// True only when the user confirms; Cancel, a tap outside and the back
/// button all give false. `meta` is a strip with one string at each end.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  SvgGenImage? icon,
  (String, String)? meta,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => _ConfirmDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      icon: icon,
      meta: meta,
    ),
  );
  return confirmed ?? false;
}

/// The one question before a downloaded file leaves the phone. [meta] is the
/// format and size strip.
Future<bool> confirmDeleteFile(
  BuildContext context,
  String name, {
  (String, String)? meta,
}) => showConfirmDialog(
  context,
  title: 'Delete this file?',
  message: '“$name” will be removed from your phone and from Gallery.',
  confirmLabel: 'Delete',
  icon: Assets.icons.trash,
  meta: meta,
);

class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.icon,
    required this.meta,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final SvgGenImage? icon;
  final (String, String)? meta;

  @override
  Widget build(BuildContext context) {
    final dialog = DialogTheme.of(context);
    final glyph = icon;
    final strip = meta;
    return Dialog(
      child: Padding(
        padding: EdgeInsets.all(Gap.xl.r),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Gap.lg.h,
          children: [
            if (glyph != null)
              ErrorIconTile(
                icon: glyph,
                size: AppSizes.dialogIconTile,
                radius: Radii.row,
                iconSize: _iconSize,
              ),
            Text(title, style: dialog.titleTextStyle),
            Text(message, style: dialog.contentTextStyle),
            if (strip != null) _MetaStrip(left: strip.$1, right: strip.$2),
            Padding(
              padding: EdgeInsets.only(top: Gap.xs.h),
              child: DialogActions(
                confirmLabel: confirmLabel,
                destructive: true,
                onConfirm: () => Navigator.of(context).pop(true),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The two buttons at the foot of a dialog: an outlined [cancelLabel] that
/// closes it with no value, and [confirmLabel].
class DialogActions extends StatelessWidget {
  const DialogActions({
    super.key,
    required this.confirmLabel,
    required this.onConfirm,
    this.cancelLabel = 'Cancel',
    this.destructive = false,
  });

  final String confirmLabel;
  final VoidCallback onConfirm;
  final String cancelLabel;
  final bool destructive;

  @override
  Widget build(BuildContext context) => Row(
    spacing: _buttonGap.w,
    children: [
      Expanded(
        child: AppButton(
          label: cancelLabel,
          variant: AppButtonVariant.outlined,
          size: AppButtonSize.medium,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      Expanded(
        child: AppButton(
          label: confirmLabel,
          variant: destructive
              ? AppButtonVariant.destructive
              : AppButtonVariant.filled,
          size: AppButtonSize.medium,
          onPressed: onConfirm,
        ),
      ),
    ],
  );
}

/// A sunken box for mono text inside a dialog: a file's format and size, or a
/// raw yt-dlp line.
class MonoPanel extends StatelessWidget {
  const MonoPanel({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: EdgeInsets.symmetric(horizontal: Gap.md.w, vertical: _metaPadY.h),
    decoration: BoxDecoration(
      color: context.tokens.bg,
      borderRadius: BorderRadius.circular(Radii.button.r),
    ),
    child: DefaultTextStyle.merge(
      style: context.type.mono.copyWith(color: context.tokens.textMuted),
      child: child,
    ),
  );
}

class _MetaStrip extends StatelessWidget {
  const _MetaStrip({required this.left, required this.right});

  final String left;
  final String right;

  @override
  Widget build(BuildContext context) {
    final style = context.type.mono.copyWith(color: context.tokens.textMuted);
    return MonoPanel(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        spacing: Gap.md.w,
        children: [
          Flexible(
            child: Text(
              left,
              style: style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(right, style: style),
        ],
      ),
    );
  }
}
