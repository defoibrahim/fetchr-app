import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../../core/config/environment.dart';
import '../../core/crash/crash_reporting.dart';
import '../../core/crash/sentry_reporter.dart';
import '../../core/gen/assets.gen.dart' show Assets;
import '../app.dart';
import '../di/core_providers.dart';
import '../theme/system_bars.dart';
import 'app_initializer.dart';
import 'provider_error_observer.dart';

final _fontLicenses = {
  'Bricolage Grotesque': Assets.fonts.bricolage.ofl,
  'Geist': Assets.fonts.geist.ofl,
  'JetBrains Mono': Assets.fonts.jetBrainsMono.ofl,
};

/// The OFL requires the licence to travel with the font; this puts it on
/// Flutter's licence page.
void registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final MapEntry(key: name, value: asset) in _fontLicenses.entries) {
      yield LicenseEntryWithLineBreaks([
        name,
      ], await rootBundle.loadString(asset));
    }
  });
}

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicenses();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    CrashReporting.recordUncaught(details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    CrashReporting.recordUncaught(error, stack);
    // Sentry chains to this handler (sentry_flutter OnErrorIntegration);
    // returning false keeps the error a crash in Sentry instead of handled.
    return false;
  };

  // Not awaited: platform messages keep their order, so the mode is set
  // before the first frame without holding the storage reads behind it.
  unawaited(enableEdgeToEdge());

  final container = ProviderContainer(
    observers: const [ProviderErrorObserver()],
  );
  await AppInitializer.init(container);
  final app = SentryWidget(
    child: UncontrolledProviderScope(
      container: container,
      child: App(
        splashGone: () =>
            container.read(fetchrHostApiProvider).awaitLaunchSplash(),
      ),
    ),
  );

  CrashReporting.add(SentryReporter());
  await SentryFlutter.init((options) {
    options.dsn =
        'https://725d369cecc1dd62beeed717e0a3d529@o4512254526750720.ingest.de.sentry.io/4512254556569680';
    options.environment = Environment.current.flavorName;
    // Replays only for sessions that hit an error. The default masking stays
    // on: every text and image is blanked in the recording.
    options.replay.sessionSampleRate = 0;
    options.replay.onErrorSampleRate = 1.0;
  }, appRunner: () => runApp(app));
}
