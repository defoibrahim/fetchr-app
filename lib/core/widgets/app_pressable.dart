import 'package:flutter/material.dart';

import 'press_scale.dart';

/// Makes [child] a tap target that answers a touch: the ink ripple, and a
/// slight shrink while the finger is down ([pressedScale], none under reduce
/// motion). A long press gets the platform's long-press feedback.
class AppPressable extends StatefulWidget {
  const AppPressable({
    super.key,
    this.onTap,
    this.onLongPress,
    required this.child,
    this.borderRadius,
    this.pressedScale = defaultPressedScale,
    this.inkAbove = false,
    this.foreground,
  }) : assert(
         foreground == null || inkAbove,
         'foreground only sits above an ink layer that is above the child',
       );

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget child;

  /// The ripple's shape; null is a rectangle.
  final BorderRadius? borderRadius;
  final double pressedScale;

  /// Ink paints under a Material's child, so an opaque picture hides it. True
  /// lays the ink over [child] instead. The ink layer then takes every touch
  /// on [child] and adds no semantics: the caller labels the child, and puts
  /// anything else tappable in [foreground].
  final bool inkAbove;

  /// Laid over the ink, the size of [child]; only its own hit targets take
  /// touches, the rest fall through to the ink.
  final Widget? foreground;

  @override
  State<AppPressable> createState() => _AppPressableState();
}

class _AppPressableState extends State<AppPressable> {
  var _pressed = false;

  void _onHighlight(bool value) {
    if (value != _pressed) setState(() => _pressed = value);
  }

  Widget _ink({Widget? child}) => Material(
    type: MaterialType.transparency,
    child: InkWell(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onHighlightChanged: _onHighlight,
      borderRadius: widget.borderRadius,
      enableFeedback: true,
      excludeFromSemantics: widget.inkAbove,
      child: child,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final foreground = widget.foreground;
    return PressScale(
      pressed: _pressed,
      scale: widget.pressedScale,
      child: widget.inkAbove
          ? Stack(
              children: [
                widget.child,
                Positioned.fill(child: _ink()),
                if (foreground != null) Positioned.fill(child: foreground),
              ],
            )
          : _ink(child: widget.child),
    );
  }
}
