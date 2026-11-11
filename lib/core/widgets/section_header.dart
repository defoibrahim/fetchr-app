import 'package:flutter/material.dart';

import '../theme/theme_extensions.dart';

/// A tab's title, announced as a header.
class ScreenTitle extends StatelessWidget {
  const ScreenTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(text, style: context.type.screenTitle),
  );
}

/// The muted caps label above a section, announced as a header.
class SectionOverline extends StatelessWidget {
  const SectionOverline(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(
      text.toUpperCase(),
      style: context.type.overline.copyWith(color: context.tokens.textMuted),
    ),
  );
}
