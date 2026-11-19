import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/theme.dart';

/// The root of a tab's page: the page's primary scroll controller, which its
/// main list picks up by itself, so a tap on the open tab can take that list
/// back to the top without the page knowing about the shell.
class TabScroll extends StatefulWidget {
  const TabScroll({super.key, required this.child});

  static const duration = Motion.emphasis;

  /// Farther down than this many screens, the list first jumps this close,
  /// so the rows in between are never built on the way up.
  static const jumpScreens = 1.5;

  final Widget child;

  @override
  State<TabScroll> createState() => TabScrollState();
}

class TabScrollState extends State<TabScroll> {
  final _controller = ScrollController();

  /// Scrolls the page's lists to their start; at once under reduce motion.
  void toTop() {
    if (!_controller.hasClients) return;
    final duration = context.motion(TabScroll.duration);
    for (final position in List.of(_controller.positions)) {
      final top = position.minScrollExtent;
      if (position.pixels <= top) continue;
      if (duration == Duration.zero) {
        position.jumpTo(top);
        continue;
      }
      final near = top + position.viewportDimension * TabScroll.jumpScreens;
      if (position.pixels > near) position.jumpTo(near);
      unawaited(
        position.animateTo(top, duration: duration, curve: Motion.standard),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      PrimaryScrollController(controller: _controller, child: widget.child);
}
