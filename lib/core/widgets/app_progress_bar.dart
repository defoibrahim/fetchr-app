import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/theme_extensions.dart';
import '../utils/scale.dart';

/// A pill-shaped bar on the sunken track. A `value` fills it; null shows a
/// 40% segment sliding across, for work with no known progress.
class AppProgressBar extends StatelessWidget {
  const AppProgressBar({
    super.key,
    this.value,
    this.height = 6,
    this.semanticsLabel = 'Download progress',
    this.color,
  });

  static const _tween = Duration(milliseconds: 250);

  final double? value;
  final double height;
  final String semanticsLabel;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final fill = color ?? context.colors.primary;
    final radius = BorderRadius.circular(Radii.pill);
    final current = value;

    // No progress-bar role: it asserts a bare number, and the spec reads "N%".
    return Semantics(
      container: true,
      label: semanticsLabel,
      value: current == null
          ? null
          : '${(current.clamp(0.0, 1.0) * 100).round()}%',
      child: ExcludeSemantics(
        child: SizedBox(
          height: height.h,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: context.tokens.surfaceSunken,
              borderRadius: radius,
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: current == null
                  ? _Sliding(color: fill, radius: radius)
                  : TweenAnimationBuilder<double>(
                      tween: Tween(end: current.clamp(0.0, 1.0)),
                      duration: context.motion(_tween),
                      builder: (context, factor, _) =>
                          _Segment(factor: factor, color: fill, radius: radius),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.factor,
    required this.color,
    required this.radius,
    this.alignment = AlignmentDirectional.centerStart,
  });

  final double factor;
  final Color color;
  final BorderRadius radius;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    widthFactor: factor,
    heightFactor: 1,
    alignment: alignment,
    child: DecoratedBox(
      decoration: BoxDecoration(color: color, borderRadius: radius),
    ),
  );
}

class _Sliding extends StatefulWidget {
  const _Sliding({required this.color, required this.radius});

  final Color color;
  final BorderRadius radius;

  @override
  State<_Sliding> createState() => _SlidingState();
}

class _SlidingState extends State<_Sliding>
    with SingleTickerProviderStateMixin {
  static const _share = .4;
  // Alignment x that parks a _share-wide segment fully off the left edge; the
  // right edge is its mirror. The span is track - segment, so off-screen is
  // beyond +-1.
  static const _edge = (1 + _share) / (1 - _share);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOut,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.reduceMotion) {
      _controller.stop();
      _controller.value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _Segment segment(AlignmentGeometry alignment) => _Segment(
      factor: _share,
      color: widget.color,
      radius: widget.radius,
      alignment: alignment,
    );
    // Held at the start edge, not off-screen, when motion is off.
    if (context.reduceMotion) return segment(Alignment.centerLeft);
    return AnimatedBuilder(
      animation: _curve,
      builder: (context, _) =>
          segment(Alignment(-_edge + 2 * _edge * _curve.value, 0)),
    );
  }
}
