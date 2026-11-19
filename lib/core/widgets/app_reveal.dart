import 'package:flutter/material.dart';

import '../theme/app_motion.dart';
import '../theme/theme_extensions.dart';
import '../utils/scale.dart';
import 'inert.dart';

/// Shows [child] by growing it from nothing while it fades in and rises 8 dp
/// into place, and hides it (null) with the reverse. The last child shown is
/// kept while it leaves, so a parent drops its data with it; while it leaves it
/// takes no taps, focus or semantics.
class AppReveal extends StatefulWidget {
  const AppReveal({super.key, required this.child});

  /// Null hides it.
  final Widget? child;

  @override
  State<AppReveal> createState() => _AppRevealState();
}

class _AppRevealState extends State<AppReveal>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this)
    ..addStatusListener(_onStatus);
  late final _curve = CurvedAnimation(
    parent: _controller,
    curve: Motion.reveal.curve,
    reverseCurve: Motion.reveal.reverseCurve,
  );
  late Widget? _shown = widget.child;
  var _mounted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _time();
    if (!_mounted) {
      _mounted = true;
      if (_visible) _controller.forward();
    }
  }

  @override
  void didUpdateWidget(AppReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    final child = widget.child;
    if (child != null) _shown = child;
    if (_visible != (oldWidget.child != null)) {
      _visible ? _controller.forward() : _controller.reverse();
    }
  }

  bool get _visible => widget.child != null;

  void _time() {
    final spec = context.motionOf(Motion.reveal);
    _controller
      ..duration = spec.duration
      ..reverseDuration = spec.reverseDuration;
  }

  // Gone for good once hidden: the kept child is dropped with it.
  void _onStatus(AnimationStatus status) {
    if (status.isDismissed && mounted) setState(() {});
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    if (shown == null || (_controller.isDismissed && !_visible)) {
      return const SizedBox.shrink();
    }
    final slide = 8.h;
    return Inert(
      inert: !_visible,
      child: SizeTransition(
        sizeFactor: _curve,
        alignment: Alignment.topCenter,
        child: FadeTransition(
          opacity: _curve,
          child: MatrixTransition(
            animation: _curve,
            onTransform: (t) =>
                Matrix4.translationValues(0, (1 - t) * slide, 0),
            child: shown,
          ),
        ),
      ),
    );
  }
}
