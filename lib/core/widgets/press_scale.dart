import 'package:flutter/widgets.dart';

import '../theme/app_motion.dart';
import '../theme/theme_extensions.dart';

const defaultPressedScale = .97;

/// Shrinks [child] to [scale] while [pressed], and not at all under reduce
/// motion.
class PressScale extends StatelessWidget {
  const PressScale({
    super.key,
    required this.pressed,
    this.scale = defaultPressedScale,
    required this.child,
  });

  final bool pressed;
  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedScale(
    scale: pressed && !context.reduceMotion ? scale : 1,
    duration: pressed ? Motion.press : Motion.fast,
    curve: Motion.standard,
    child: child,
  );
}
