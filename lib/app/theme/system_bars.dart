import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/logging/app_logger.dart';
import '../../core/theme/theme.dart';

/// Lets the app draw behind the status and navigation bars; [SystemBars]
/// colours them. A failure is logged: the bars then keep the system's look.
Future<void> enableEdgeToEdge() async {
  try {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  } catch (e, s) {
    AppLogger.error('Could not go edge to edge', e, s);
  }
}

/// Transparent status and navigation bars, with icons that read on the theme
/// in force. The app paints under both: the shell's bar fills the gesture
/// area with `navBar`, and a sheet's scrim dims it like the rest. Sits below
/// the Theme, so it follows a switch between light and dark.
class SystemBars extends StatelessWidget {
  const SystemBars({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: systemBarsStyle(
        context.isDark ? Brightness.light : Brightness.dark,
      ),
      child: child,
    );
  }
}

/// Transparent bars with [icons] icons, the one style the app gives them.
SystemUiOverlayStyle systemBarsStyle(Brightness icons) => SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: icons,
  systemNavigationBarColor: Colors.transparent,
  systemNavigationBarIconBrightness: icons,
  // The shell draws its own 1 dp line; the system adds neither a divider nor a
  // scrim over what the app paints there.
  systemNavigationBarDividerColor: Colors.transparent,
  systemNavigationBarContrastEnforced: false,
  systemStatusBarContrastEnforced: false,
);
