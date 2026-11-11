import 'package:flutter/material.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/theme_extensions.dart';
import '../../../../../core/utils/scale.dart';
import '../../../../../core/widgets/section_header.dart';

const _titleGap = 10.0;
const _cardPadding = 14.0;
const _rowGap = 14.0;
const _textGap = 3.0;

/// An overline title over a card; each of `rows` is one group, and a hairline
/// divider separates the groups.
class SettingsSection extends StatelessWidget {
  const SettingsSection({super.key, required this.title, required this.rows});

  final String title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: _titleGap.h,
      children: [
        SectionOverline(title),
        // A Material, not a DecoratedBox: an opaque box over the page's Material
        // would hide the ripple of a tappable row.
        Material(
          color: tokens.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.card.r),
            side: BorderSide(color: tokens.border),
          ),
          child: Padding(
            padding: EdgeInsets.all(_cardPadding.r),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: _rowGap.h,
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) Divider(color: tokens.surfaceSunken),
                  rows[i],
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A row's title over its control, such as a group of pills.
class SettingsField extends StatelessWidget {
  const SettingsField({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: _titleGap.h,
      children: [
        Text(title, style: context.type.bodyStrong),
        child,
      ],
    );
  }
}

/// A title and a muted line on the left, a switch on the right. A null
/// `onChanged` disables the switch.
class SettingsSwitchRow extends StatelessWidget {
  const SettingsSwitchRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final type = context.type;
    return MergeSemantics(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: AppSizes.buttonMedium.h),
        child: Row(
          spacing: Gap.md.w,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: _textGap.h,
                children: [
                  Text(title, style: type.bodyStrong),
                  Text(
                    subtitle,
                    style: type.caption.copyWith(
                      color: context.tokens.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}
