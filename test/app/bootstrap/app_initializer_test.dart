import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/app/bootstrap/app_initializer.dart';
import 'package:grabby/app/di/core_providers.dart';
import 'package:grabby/app/shared/domain/entities/quality.dart';
import 'package:grabby/app/shared/download_prefs_provider.dart';
import 'package:grabby/app/theme/accent_provider.dart';
import 'package:grabby/core/logging/app_logger.dart';
import 'package:grabby/core/networking/interceptors.dart';
import 'package:grabby/core/services/storage/app_storage.dart';
import 'package:grabby/core/theme/theme.dart';
import 'package:mocktail/mocktail.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../support/memory_storage.dart';
import '../../support/mocks.dart';

const _channel = MethodChannel('flutter.baseflow.com/permissions/methods');

void main() {
  final requests = <List<Object?>>[];
  late MockFetchrHostApi host;

  // `containerWith` has no room for the host API, which init now calls.
  ProviderContainer containerFor(AppStorage storage) => containerWith(
    storage,
    overrides: [fetchrHostApiProvider.overrideWithValue(host)],
  );

  setUpAll(() => registerFallbackValue(0));

  void answerPermissions(Future<Object?> Function() reply) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) {
          if (call.method == 'requestPermissions') {
            requests.add(call.arguments as List<Object?>);
          }
          return reply();
        });
  }

  setUp(() {
    requests.clear();
    host = MockFetchrHostApi();
    when(() => host.setAccentColor(any())).thenAnswer((_) async {});
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    AppInterceptors.onUnauthorized = null;
    AppLogger.reset();
  });

  testWidgets('init loads the saved download prefs before the first frame', (
    tester,
  ) async {
    answerPermissions(() async => <int, int>{});
    final container = containerFor(
      MemoryStorage({
        StorageKeys.defaultQuality: 'p480',
        StorageKeys.saveFolder: 'Clips',
        StorageKeys.useAria2c: 'true',
      }),
    );
    addTearDown(container.dispose);

    await AppInitializer.init(container);

    expect(
      container.read(downloadPrefsProvider),
      const DownloadPrefs(
        quality: Quality.p480,
        folder: 'Clips',
        useAria2c: true,
      ),
    );
    expect(requests, isEmpty, reason: 'permissions wait for the first frame');
  });

  testWidgets('init sends the loaded accent to native once', (tester) async {
    answerPermissions(() async => <int, int>{});
    final blue = AppPalette.accents[1].color;
    final container = containerFor(
      MemoryStorage({StorageKeys.accent: '${blue.toARGB32()}'}),
    );
    addTearDown(container.dispose);

    await AppInitializer.init(container);

    expect(container.read(accentProvider), blue);
    verify(() => host.setAccentColor(blue.toARGB32())).called(1);
    verifyNoMoreInteractions(host);
  });

  testWidgets('a native failure while sending the accent does not stop init', (
    tester,
  ) async {
    final lines = <String>[];
    AppLogger.overrideForTesting(sink: (_, message, _) => lines.add(message));
    answerPermissions(() async => <int, int>{});
    when(
      () => host.setAccentColor(any()),
    ).thenAnswer((_) async => throw PlatformException(code: 'channel-error'));
    final container = containerFor(MemoryStorage());
    addTearDown(container.dispose);

    await AppInitializer.init(container);
    await tester.pump();

    expect(lines.single, startsWith('Could not send the accent to native'));
  });

  testWidgets('permissions are requested once, after the first frame', (
    tester,
  ) async {
    answerPermissions(() async => <int, int>{});
    final container = containerFor(MemoryStorage());
    addTearDown(container.dispose);

    await AppInitializer.init(container);
    await tester.pumpWidget(const SizedBox());

    expect(requests, [
      [
        Permission.notification.value,
        Permission.storage.value,
        Permission.videos.value,
        Permission.audio.value,
      ],
    ]);
  });

  testWidgets('a failing permission request is logged, not thrown', (
    tester,
  ) async {
    final lines = <String>[];
    AppLogger.overrideForTesting(sink: (_, message, _) => lines.add(message));
    answerPermissions(() async => throw PlatformException(code: 'boom'));
    final container = containerFor(MemoryStorage());
    addTearDown(container.dispose);

    await AppInitializer.init(container);
    await tester.pumpWidget(const SizedBox());

    expect(lines.single, startsWith('Could not request permissions'));
  });
}
