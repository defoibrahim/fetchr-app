import 'package:flutter/widgets.dart';

/// Where the launch intro's logo tile lands: the Home header puts [tileKey] on
/// its own tile so the intro can find the rect to fly to.
class LaunchLogoTarget extends InheritedWidget {
  const LaunchLogoTarget({
    super.key,
    required this.tileKey,
    required super.child,
  });

  final GlobalKey tileKey;

  /// Null outside the launch intro. The key never changes, so the header does
  /// not depend on it.
  static GlobalKey? keyOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<LaunchLogoTarget>()?.tileKey;

  @override
  bool updateShouldNotify(LaunchLogoTarget oldWidget) =>
      tileKey != oldWidget.tileKey;
}
