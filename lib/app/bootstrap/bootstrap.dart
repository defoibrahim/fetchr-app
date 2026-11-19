import 'dart:async';
import 'dart:convert' show jsonDecode;
import 'dart:io' show Platform;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry, defaultTargetPlatform;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../../core/config/environment.dart';
import '../../core/crash/crash_reporting.dart';
import '../../core/crash/crash_reporting_policy.dart';
import '../../core/crash/sentry_reporter.dart';
import '../../core/gen/assets.gen.dart' show Assets;
import '../../core/platform/platform_traits.dart';
import '../app.dart';
import '../di/core_providers.dart';
import '../launch/launch_intro.dart';
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
void registerFontLicenses() => _addLicenses(
  () async => _fontLicenses.entries.map((e) => (e.key, e.value)),
);

/// Python, FFmpeg and the Python packages ship inside the iOS app; their
/// licences go on the licence page next to the Dart packages'.
void registerNativeLicenses(PlatformTraits traits) {
  final manifest = traits.nativeLicenseManifest;
  if (manifest == null) return;
  _addLicenses(() async {
    final entries = jsonDecode(await rootBundle.loadString(manifest)) as List;
    return [
      for (final entry in entries.cast<Map<String, dynamic>>())
        (entry['name'] as String, entry['file'] as String),
    ];
  });
}

void _addLicenses(Future<Iterable<(String, String)>> Function() entries) {
  LicenseRegistry.addLicense(() async* {
    for (final (name, asset) in await entries()) {
      yield LicenseEntryWithLineBreaks([
        name,
      ], await rootBundle.loadString(asset));
    }
  });
}

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicenses();
  registerNativeLicenses(PlatformTraits.of(defaultTargetPlatform));

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
  // A notification tap opens its own screen (fetchr://app/...), which the
  // intro would cover and then have no Home header to land on.
  final deepLinked = launchedOnDeepLink(
    PlatformDispatcher.instance.defaultRouteName,
  );
  final app = SentryWidget(
    child: UncontrolledProviderScope(
      container: container,
      child: App(
        splashGone: deepLinked
            ? null
            : () => container.read(fetchrHostApiProvider).awaitLaunchSplash(),
      ),
    ),
  );

  CrashReporting.add(SentryReporter());
  await SentryFlutter.init((options) {
    // An empty DSN turns Sentry off, native hang reports included.
    options.dsn = reportsCrashes(Platform.environment)
        ? 'https://725d369cecc1dd62beeed717e0a3d529@o4512254526750720.ingest.de.sentry.io/4512254556569680'
        : '';
    options.environment = Environment.current.flavorName;
    // Replays only for sessions that hit an error. The default masking stays
    // on: every text and image is blanked in the recording.
    options.replay.sessionSampleRate = 0;
    options.replay.onErrorSampleRate = 1.0;
  }, appRunner: () => runApp(app));
}
