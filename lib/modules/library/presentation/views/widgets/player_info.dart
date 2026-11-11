import 'package:flutter/material.dart';

import '../../../../../core/gen/assets.gen.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/theme_extensions.dart';
import '../../../../../core/utils/formatters.dart';
import '../../../../../core/utils/scale.dart';
import '../../../../../core/widgets/app_icon.dart';
import '../../../domain/entities/library_item.dart';
import '../../formatters/library_item_formatter.dart';

const _actionHeight = 52.0;
const _actionGap = 10.0;
const _rowPadY = 12.0;
const _rowGap = 16.0;
const _locationGap = 6.0;
const _locationLineHeight = 1.5;

/// Share and Delete side by side. Neither is an AppButton variant: Share is a
/// surface with the control border, Delete the error surface.
class PlayerActions extends StatelessWidget {
  const PlayerActions({
    super.key,
    required this.onShare,
    required this.onDelete,
  });

  final VoidCallback onShare;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Row(
      spacing: _actionGap.w,
      children: [
        Expanded(
          child: _ActionButton(
            icon: Assets.icons.share,
            label: 'Share',
            fill: tokens.surface,
            border: tokens.borderControl,
            ink: tokens.text,
            onPressed: onShare,
          ),
        ),
        Expanded(
          child: _ActionButton(
            icon: Assets.icons.trash,
            label: 'Delete',
            fill: tokens.errorSurface,
            border: tokens.errorBorder,
            ink: tokens.error,
            onPressed: onDelete,
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.fill,
    required this.border,
    required this.ink,
    required this.onPressed,
  });

  final SvgGenImage icon;
  final String label;
  final Color fill;
  final Color border;
  final Color ink;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: Size.fromHeight(_actionHeight.h),
        backgroundColor: fill,
        foregroundColor: ink,
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.row.r),
        ),
        textStyle: context.type.bodyStrong,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: _actionGap.w,
        children: [
          AppIcon(icon, size: AppSizes.iconButton.r),
          Flexible(child: Text(label)),
        ],
      ),
    );
  }
}

/// Quality, size, when it was saved and where: a card of label and value rows.
class PlayerInfoList extends StatelessWidget {
  const PlayerInfoList({super.key, required this.item});

  final LibraryItem item;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final divider = Divider(color: tokens.surfaceSunken);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: Gap.lg.w, vertical: Gap.xs.h),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(Radii.control.r),
      ),
      child: Column(
        children: [
          _Row(label: 'Quality', value: item.formatLabel),
          divider,
          _Row(label: 'Size', value: formatBytes(item.sizeBytes)),
          divider,
          _Row(label: 'Saved', value: formatDateTime(item.dateAdded)),
          divider,
          _Location(value: item.location),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final type = context.type;
    return MergeSemantics(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: _rowPadY.h),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          spacing: _rowGap.w,
          children: [
            Text(
              label,
              style: type.caption.copyWith(color: context.tokens.textMuted),
            ),
            // Sizes and quality read left to right whatever the locale.
            Flexible(
              child: Text(
                value,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.end,
                style: type.mono,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Location extends StatelessWidget {
  const _Location({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    final type = context.type;
    return MergeSemantics(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: _rowPadY.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: _locationGap.h,
          children: [
            Text(
              'Location',
              style: type.caption.copyWith(color: context.tokens.textMuted),
            ),
            // A path is left to right whatever the locale.
            Text(
              value,
              textDirection: TextDirection.ltr,
              style: type.mono.copyWith(height: _locationLineHeight),
            ),
          ],
        ),
      ),
    );
  }
}
