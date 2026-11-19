import 'package:flutter/widgets.dart';

/// Where the launch intro's logo tile lands: the Home header puts [tileKey] on
/// its own tile so the intro can find the rect to fly to. Home also ends the
/// intro through [skipIntro] when the app opens on a shared link.
class LaunchLogoTarget extends InheritedWidget {
  const LaunchLogoTarget({
    super.key,
    required this.tileKey,
    required this.skipIntro,
    required super.child,
  });

  final GlobalKey tileKey;
  final VoidCallback skipIntro;

  /// Null outside the launch intro. The key never changes, so the header does
  /// not depend on it.
  static GlobalKey? keyOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<LaunchLogoTarget>()?.tileKey;

  /// Ends the launch intro at once; nothing outside it.
  static void skipIntroOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<LaunchLogoTarget>()?.skipIntro();

  @override
  bool updateShouldNotify(LaunchLogoTarget oldWidget) =>
      tileKey != oldWidget.tileKey;
}
