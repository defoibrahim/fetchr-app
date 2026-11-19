import 'package:flutter/material.dart';

import '../theme/app_motion.dart';
import '../theme/theme_extensions.dart';

/// A spinner that waits [Motion.spinnerDelay] before it shows, then fades in
/// over [Motion.fast]: a load that ends sooner never flashes it. Under reduce
/// motion it still waits, then appears without the fade.
class LoadingView extends StatefulWidget {
  const LoadingView({super.key});

  @override
  State<LoadingView> createState() => _LoadingViewState();
}

class _LoadingViewState extends State<LoadingView>
    with SingleTickerProviderStateMixin {
  static final _split =
      Motion.spinnerDelay.inMicroseconds /
      (Motion.spinnerDelay + Motion.fast).inMicroseconds;

  // Preserve: the wait is timing, not motion, and must not shrink under
  // reduce motion the way a normal controller's duration does.
  late final _controller = AnimationController(
    vsync: this,
    duration: Motion.spinnerDelay + Motion.fast,
    animationBehavior: AnimationBehavior.preserve,
  )..forward();
  late final _opacity = CurvedAnimation(parent: _controller, curve: _fadeIn);

  static final _fadeIn = Interval(_split, 1, curve: Motion.standard);
  static final _appear = Threshold(_split);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _opacity.curve = context.reduceMotion ? _appear : _fadeIn;
  }

  @override
  void dispose() {
    _opacity.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _opacity,
    child: const Center(child: CircularProgressIndicator()),
  );
}
