import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// The app's route transitions: the platform's own (on Android the predictive
/// back one, which lets a back swipe peek at the page underneath), made
/// instant under "Remove animations".
abstract final class AppPageTransitions {
  static const theme = PageTransitionsTheme(
    builders: {
      TargetPlatform.android: ReduceMotionPageTransitionsBuilder(
        PredictiveBackPageTransitionsBuilder(),
      ),
      TargetPlatform.iOS: ReduceMotionPageTransitionsBuilder(
        CupertinoPageTransitionsBuilder(),
      ),
    },
  );
}

/// [builder]'s transition with no duration when the user asked for less
/// motion: a push and a pop both land on the next frame. The builder still
/// builds, so the platform's back gesture detectors stay in the tree.
class ReduceMotionPageTransitionsBuilder extends PageTransitionsBuilder {
  const ReduceMotionPageTransitionsBuilder(this.builder);

  final PageTransitionsBuilder builder;

  // A route reads its durations once, when it is pushed, and without a
  // context: this is the flag MediaQuery.disableAnimations comes from.
  static bool get _reduced => WidgetsBinding
      .instance
      .platformDispatcher
      .accessibilityFeatures
      .disableAnimations;

  @override
  Duration get transitionDuration =>
      _reduced ? Duration.zero : builder.transitionDuration;

  @override
  Duration get reverseTransitionDuration =>
      _reduced ? Duration.zero : builder.reverseTransitionDuration;

  @override
  DelegatedTransitionBuilder? get delegatedTransition =>
      _reduced ? null : builder.delegatedTransition;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => builder.buildTransitions(
    route,
    context,
    animation,
    secondaryAnimation,
    child,
  );
}
