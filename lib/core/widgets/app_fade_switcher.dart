import 'package:flutter/material.dart';

import '../theme/app_motion.dart';
import '../theme/theme_extensions.dart';
import 'inert.dart';

/// Cross-fades (and slightly scales) from one child to the next. Key [child]
/// by the kind of state it shows (`ValueKey(isLoading)`, `ValueKey('paused')`),
/// never by data that changes on every tick, or every tick restarts the fade.
///
/// The outgoing child takes no taps, focus or semantics while it fades, so a
/// quick second tap cannot fire the action it used to offer.
class AppFadeSwitcher extends StatelessWidget {
  const AppFadeSwitcher({
    super.key,
    required this.child,
    this.spec = Motion.swap,
    this.scaleFrom = .98,
    this.alignment = Alignment.topCenter,
    this.sizeToIncoming = false,
  });

  final Widget child;
  final MotionSpec spec;

  /// The incoming child's scale at the start of its fade; 1 for none.
  final double scaleFrom;
  final AlignmentGeometry alignment;

  /// The outgoing child stops counting toward the width once it starts to
  /// leave, so a Row neighbour (an Expanded field) resizes once, on the swap,
  /// not in a jump when the fade ends. It still paints, overflowing at
  /// [alignment].
  final bool sizeToIncoming;

  @override
  Widget build(BuildContext context) {
    final motion = context.motionOf(spec);
    return AnimatedSwitcher(
      duration: motion.duration,
      reverseDuration: motion.reverseDuration,
      switchInCurve: motion.curve,
      switchOutCurve: motion.reverseCurve ?? motion.curve,
      transitionBuilder: _transition,
      layoutBuilder: _layout,
      child: child,
    );
  }

  Widget _transition(Widget child, Animation<double> animation) {
    return _Settling(
      animation: animation,
      alignment: alignment,
      collapseWhenLeaving: sizeToIncoming,
      scaleFrom: scaleFrom,
      child: child,
    );
  }

  Widget _layout(Widget? current, List<Widget> previous) =>
      Stack(alignment: alignment, children: [...previous, ?current]);
}

/// Shuts an outgoing child off from input. AnimatedSwitcher plays the
/// outgoing child's animation in reverse, so the status tells the two apart
/// without moving the child in the tree, which would rebuild its state.
class _Settling extends StatefulWidget {
  const _Settling({
    required this.animation,
    required this.alignment,
    required this.collapseWhenLeaving,
    required this.scaleFrom,
    required this.child,
  });

  final Animation<double> animation;
  final AlignmentGeometry alignment;
  final bool collapseWhenLeaving;
  final double scaleFrom;
  final Widget child;

  @override
  State<_Settling> createState() => _SettlingState();
}

class _SettlingState extends State<_Settling> {
  bool get _leaving => switch (widget.animation.status) {
    AnimationStatus.reverse || AnimationStatus.dismissed => true,
    AnimationStatus.forward || AnimationStatus.completed => false,
  };

  late bool _wasLeaving = _leaving;
  late Animation<double> _scale = _scaleOf(widget);

  Animation<double> _scaleOf(_Settling w) =>
      Tween(begin: w.scaleFrom, end: 1.0).animate(w.animation);

  @override
  void initState() {
    super.initState();
    widget.animation.addStatusListener(_onStatus);
  }

  @override
  void didUpdateWidget(_Settling oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation) {
      oldWidget.animation.removeStatusListener(_onStatus);
      widget.animation.addStatusListener(_onStatus);
      _wasLeaving = _leaving;
    }
    if (oldWidget.animation != widget.animation ||
        oldWidget.scaleFrom != widget.scaleFrom) {
      _scale = _scaleOf(widget);
    }
  }

  @override
  void dispose() {
    widget.animation.removeStatusListener(_onStatus);
    super.dispose();
  }

  // Only a flip between coming and going rebuilds, not every status.
  void _onStatus(AnimationStatus _) {
    if (_leaving != _wasLeaving) setState(() => _wasLeaving = _leaving);
  }

  @override
  Widget build(BuildContext context) {
    final leaving = _wasLeaving;
    var child =
        FadeTransition(opacity: widget.animation, child: widget.child)
            as Widget;
    if (widget.scaleFrom != 1) {
      child = ScaleTransition(scale: _scale, child: child);
    }
    if (widget.collapseWhenLeaving) {
      // Always an Align, so the child is never moved in the tree.
      child = Align(
        alignment: widget.alignment,
        widthFactor: leaving ? 0 : 1,
        heightFactor: 1,
        child: child,
      );
    }
    return Inert(inert: leaving, child: child);
  }
}
