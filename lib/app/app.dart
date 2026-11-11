import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/environment.dart';
import '../core/theme/theme.dart';
import '../core/utils/scale.dart';
import 'launch/launch_intro.dart';
import 'routes/app_router.dart';
import 'theme/accent_provider.dart';
import 'theme/system_bars.dart';
import 'theme/theme_mode_provider.dart';

class App extends ConsumerWidget {
  const App({super.key, this.splashGone});

  /// Completes when the native splash is gone. When set, the app opens with
  /// the launch intro over the first screen; tests leave it out.
  final Future<void> Function()? splashGone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = ref.watch(accentProvider);
    final gone = splashGone;
    return ScaleScope(
      child: MaterialApp.router(
        title: Environment.current.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(accent),
        darkTheme: AppTheme.dark(accent),
        themeMode: ref.watch(themeModeProvider),
        routerConfig: ref.watch(routerProvider),
        // Screens are laid out in fixed .w/.h boxes for 375x812; text much
        // past 1.3x overflows them.
        builder: (context, child) => SystemBars(
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
              child: gone == null || child == null
                  ? child
                  : LaunchIntro(splashGone: gone, child: child),
            ),
          ),
        ),
      ),
    );
  }
}
