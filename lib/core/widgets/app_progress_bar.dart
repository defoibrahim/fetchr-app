import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';
import '../theme/theme_extensions.dart';
import '../utils/scale.dart';
import 'app_fade_switcher.dart';

/// A pill-shaped bar on the sunken track. A `value` fills it; null shows a
/// 40% segment sliding across, for work with no known progress.
///
/// The fill moves at a steady speed: each new value tweens linearly over the
/// time the last one took to arrive (about 250 ms from native, 1 s from
/// aria2c), so the bar neither jumps nor rests between updates.
class AppProgressBar extends StatefulWidget {
  const AppProgressBar({
    super.key,
    this.value,
    this.height = 6,
    this.semanticsLabel = 'Download progress',
    this.color,
  });

  /// The tween before two updates have given a gap to match.
  static const firstTween = Motion.medium;
  static const minTween = Motion.fast;
  static const maxTween = Duration(milliseconds: 1200);

  final double? value;
  final double height;
  final String semanticsLabel;
  final Color? color;

  @override
  State<AppProgressBar> createState() => _AppProgressBarState();
}

class _AppProgressBarState extends State<AppProgressBar> {
  var _tween = AppProgressBar.firstTween;
  Duration? _changedAt;

  // A frame's time stamp, which a test's pump advances too; null outside a
  // frame, where nothing is measured.
  static Duration? get _now {
    final binding = SchedulerBinding.instance;
    return binding.schedulerPhase == SchedulerPhase.idle
        ? null
        : binding.currentFrameTimeStamp;
  }

  @override
  void didUpdateWidget(AppProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final value = widget.value;
    if (value == oldWidget.value) return;
    final now = _now;
    if (value == null || oldWidget.value == null) {
      // A new run of values: its first gap is unknown.
      _tween = AppProgressBar.firstTween;
      _changedAt = value == null ? null : now;
      return;
    }
    final last = _changedAt;
    if (now != null && last != null) {
      _tween = _clamp(now - last);
    }
    _changedAt = now;
  }

  static Duration _clamp(Duration gap) => gap < AppProgressBar.minTween
      ? AppProgressBar.minTween
      : gap > AppProgressBar.maxTween
      ? AppProgressBar.maxTween
      : gap;

  @override
  Widget build(BuildContext context) {
    final fill = widget.color ?? context.colors.primary;
    final radius = BorderRadius.circular(Radii.pill);
    final current = widget.value;

    // No progress-bar role: it asserts a bare number, and the spec reads "N%".
    return Semantics(
      container: true,
      label: widget.semanticsLabel,
      value: current == null
          ? null
          : '${(current.clamp(0.0, 1.0) * 100).round()}%',
      child: ExcludeSemantics(
        child: SizedBox(
          height: widget.height.h,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: context.tokens.surfaceSunken,
              borderRadius: radius,
            ),
            // The fill repaints every frame of a tween; the card around it
            // need not.
            child: RepaintBoundary(
              child: ClipRRect(
                borderRadius: radius,
                // The paused colour eases in rather than snapping.
                child: TweenAnimationBuilder<Color?>(
                  tween: ColorTween(end: fill),
                  duration: context.motion(Motion.fast),
                  builder: (context, color, _) => SizedBox.expand(
                    child: AppFadeSwitcher(
                      spec: Motion.crossFade,
                      scaleFrom: 1,
                      alignment: AlignmentDirectional.centerStart,
                      // Each fills the track: the segments place themselves
                      // within it.
                      child: current == null
                          ? SizedBox.expand(
                              key: const ValueKey('sliding'),
                              child: _Sliding(
                                color: color ?? fill,
                                radius: radius,
                              ),
                            )
                          : SizedBox.expand(
                              key: const ValueKey('fill'),
                              child: TweenAnimationBuilder<double>(
                                tween: Tween(end: current.clamp(0.0, 1.0)),
                                duration: context.motion(_tween),
                                builder: (context, factor, _) => _Segment(
                                  factor: factor,
                                  color: color ?? fill,
                                  radius: radius,
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
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
