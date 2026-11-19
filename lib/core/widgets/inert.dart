import 'package:flutter/widgets.dart';

/// While [inert], the child takes no taps or focus and is not read out: what is
/// on its way out of the screen.
class Inert extends StatelessWidget {
  const Inert({super.key, required this.inert, required this.child});

  final bool inert;
  final Widget child;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: inert,
    child: ExcludeSemantics(
      excluding: inert,
      child: ExcludeFocus(excluding: inert, child: child),
    ),
  );
}
