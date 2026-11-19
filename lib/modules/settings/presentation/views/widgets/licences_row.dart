import 'package:flutter/material.dart';

import '../../../../../core/config/environment.dart';
import '../../../../../core/gen/assets.gen.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/theme_extensions.dart';
import '../../../../../core/utils/scale.dart';
import '../../../../../core/widgets/app_icon.dart';

const _chevron = 18.0;
const _textGap = 3.0;

/// Opens Flutter's licence page: the Dart packages, the fonts' OFL and, on
/// iOS, what the native layer bundles.
class LicencesRow extends StatelessWidget {
  const LicencesRow({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final type = context.type;
    return MergeSemantics(
      child: Semantics(
        button: true,
        child: InkWell(
          // Above the tab bar, like the player.
          onTap: () => showLicensePage(
            context: context,
            applicationName: Environment.current.appName,
            useRootNavigator: true,
          ),
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
                      Text('Open-source licences', style: type.bodyStrong),
                      Text(
                        'The software Fetchr is built with',
                        style: type.caption.copyWith(color: tokens.textMuted),
                      ),
                    ],
                  ),
                ),
                AppIcon(
                  Assets.icons.chevronRight,
                  size: _chevron.r,
                  color: tokens.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
