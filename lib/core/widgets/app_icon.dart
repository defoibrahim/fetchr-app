import 'package:flutter/widgets.dart';

import '../gen/assets.gen.dart';

/// An icon from `assets/icons`, tinted with a srcIn colour filter. Not
/// `SvgTheme(currentColor:)`: that makes every colour its own flutter_svg cache
/// key, so a theme lerp or an accent change re-parses each visible icon.
class AppIcon extends StatelessWidget {
  const AppIcon(
    this.icon, {
    super.key,
    this.size,
    this.color,
    this.semanticLabel,
  });

  final SvgGenImage icon;
  final double? size;
  final Color? color;

  // Null means decorative: the icon is left out of the semantics tree.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final side = size ?? theme.size ?? 24;
    final tint = color ?? theme.color;
    return icon.svg(
      width: side,
      height: side,
      colorFilter: tint == null
          ? null
          : ColorFilter.mode(tint, BlendMode.srcIn),
      semanticsLabel: semanticLabel,
      excludeFromSemantics: semanticLabel == null,
    );
  }
}
