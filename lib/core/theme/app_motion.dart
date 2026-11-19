import 'package:flutter/material.dart';

/// One movement: how long it takes and how it eases, and, when it plays
/// backwards (an exit, a hide), how long and how that eases.
@immutable
class MotionSpec {
  const MotionSpec(
    this.duration,
    this.curve, {
    this.reverseDuration,
    this.reverseCurve,
  });

  final Duration duration;
  final Curve curve;

  /// Null plays the exit like the entry.
  final Duration? reverseDuration;
  final Curve? reverseCurve;

  /// The spec with every duration at zero, for "Remove animations".
  MotionSpec get instant => MotionSpec(
    Duration.zero,
    curve,
    reverseDuration: reverseDuration == null ? null : Duration.zero,
    reverseCurve: reverseCurve,
  );

  @override
  bool operator ==(Object other) =>
      other is MotionSpec &&
      other.duration == duration &&
      other.curve == curve &&
      other.reverseDuration == reverseDuration &&
      other.reverseCurve == reverseCurve;

  @override
  int get hashCode =>
      Object.hash(duration, curve, reverseDuration, reverseCurve);
}

/// The app's motion tokens, on Material 3's durations and easings. An exit is
/// shorter than its entry: what leaves should get out of the way.
abstract final class Motion {
  /// A finger going down: the press scale.
  static const press = Durations.short2;

  /// Small swaps and fades: a finger coming up, an icon, a status line.
  static const fast = Durations.short3;
  static const base = Durations.short4;
  static const medium = Durations.medium1;
  static const emphasis = Durations.medium2;

  /// How long work may run before a spinner is worth showing.
  static const spinnerDelay = Duration(milliseconds: 200);

  static const standard = Easing.standard;
  static const enter = Easing.emphasizedDecelerate;
  static const exit = Easing.emphasizedAccelerate;

  /// Overshoots: badges and checks only, never a layout.
  static const pop = Curves.easeOutBack;

  static const fade = MotionSpec(fast, standard);

  /// A cross-fade between two whole layouts: a filtered grid, a bar's state.
  static const crossFade = MotionSpec(base, standard);
  static const swap = MotionSpec(
    base,
    enter,
    reverseDuration: fast,
    reverseCurve: exit,
  );
  static const reveal = MotionSpec(
    medium,
    enter,
    reverseDuration: base,
    reverseCurve: exit,
  );
}
