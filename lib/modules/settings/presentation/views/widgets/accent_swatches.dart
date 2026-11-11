import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';

import '../../../../../core/gen/assets.gen.dart';
import '../../../../../core/theme/app_palette.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/theme_extensions.dart';
import '../../../../../core/utils/scale.dart';
import '../../../../../core/widgets/app_icon.dart';

const _swatchSize = 32.0;
const _ringWidth = 2.0;
const _checkSize = 16.0;

/// One 32 dp swatch per palette accent in a 44 dp target, which leaves the
/// spec's 12 dp between swatches. The selected one has a ring and a check, so
/// colour is never the only cue.
class AccentSwatches extends StatelessWidget {
  const AccentSwatches({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final Color selected;
  final ValueChanged<Color> onSelected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      role: SemanticsRole.radioGroup,
      label: 'Accent',
      child: Row(
        children: [
          for (final accent in AppPalette.accents)
            _Swatch(
              name: accent.name,
              color: accent.color,
              selected: accent.color == selected,
              onTap: () => onSelected(accent.color),
            ),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.name,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Semantics(
      container: true,
      excludeSemantics: true,
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: '$name accent',
      onTap: onTap,
      child: InkResponse(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox.square(
          dimension: AppSizes.touch.r,
          child: Center(
            child: Container(
              width: _swatchSize.r,
              height: _swatchSize.r,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                border: selected
                    ? Border.all(color: tokens.text, width: _ringWidth)
                    : null,
              ),
              child: selected
                  ? Center(
                      child: AppIcon(
                        Assets.icons.check,
                        size: _checkSize.r,
                        color: tokens.onAccent,
                      ),
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}
