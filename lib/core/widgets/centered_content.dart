import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/theme_extensions.dart';

/// Caps a page at [Breakpoints.contentMax] and centres it in the room it
/// gets. Under [Breakpoints.medium] it adds no inset, so a phone is laid out
/// exactly as before.
class CenteredContent extends StatelessWidget {
  const CenteredContent({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final capped = context.windowClass.isAtLeast(WindowClass.medium);
    // One tree on both sides of 600 dp, so rotating a phone keeps the page's
    // State. Padding, not Align: the child keeps its constraints, so it fills
    // the width under 600 and a loose-height slot still shrinks to it.
    return LayoutBuilder(
      builder: (_, constraints) => Padding(
        padding: EdgeInsets.symmetric(
          // An unbounded width (a horizontal scroll view) has no room to split.
          horizontal: capped && constraints.hasBoundedWidth
              ? max(0.0, (constraints.maxWidth - Breakpoints.contentMax) / 2)
              : 0,
        ),
        child: child,
      ),
    );
  }
}
