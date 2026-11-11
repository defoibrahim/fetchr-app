import 'package:flutter/material.dart';

import '../theme/theme_extensions.dart';
import '../utils/scale.dart';

class AppText extends StatelessWidget {
  const AppText(
    this.text, {
    super.key,
    this.size,
    this.weight,
    this.color,
    this.maxLines,
    this.align,
    this.style,
  });

  final String text;
  final double? size;
  final FontWeight? weight;
  final Color? color;
  final int? maxLines;
  final TextAlign? align;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final base = style ?? context.text.bodyMedium ?? const TextStyle();
    return Text(
      text,
      maxLines: maxLines,
      textAlign: align,
      overflow: TextOverflow.ellipsis,
      style: base.copyWith(
        color: color ?? base.color ?? context.tokens.text,
        fontSize: size?.sp,
        fontWeight: weight,
      ),
    );
  }
}
