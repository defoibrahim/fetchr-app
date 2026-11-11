import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/app/di/core_providers.dart';
import 'package:grabby/app/theme/accent_provider.dart';
import 'package:grabby/core/logging/app_logger.dart';
import 'package:grabby/core/services/storage/app_storage.dart';
import 'package:grabby/core/theme/theme.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/memory_storage.dart';
import '../../support/mocks.dart';

void main() {
  late MockFetchrHostApi host;

  setUpAll(() => registerFallbackValue(0));

  setUp(() {
    host = MockFetchrHostApi();
    when(() => host.setAccentColor(any())).thenAnswer((_) async {});
  });

  tearDown(AppLogger.reset);

  final blue = AppPalette.accents[1].color;

  ProviderContainer containerFor(AppStorage storage) => containerWith(
    storage,
    overrides: [fetchrHostApiProvider.overrideWithValue(host)],
  );

  test('starts as lime with nothing saved', () async {
    final container = containerFor(MemoryStorage());
    addTearDown(container.dispose);

    expect(container.read(accentProvider), AppPalette.defaultAccent);
    await container.read(accentProvider.notifier).load();
    expect(container.read(accentProvider), AppPalette.defaultAccent);
  });

  test('load restores a saved ARGB value', () async {
    final container = containerFor(
      MemoryStorage({StorageKeys.accent: '${blue.toARGB32()}'}),
    );
    addTearDown(container.dispose);

    await container.read(accentProvider.notifier).load();

    expect(container.read(accentProvider), blue);
  });

  test('an unknown or unreadable saved value falls back to lime', () async {
    for (final saved in ['4294967295', 'blue', '']) {
      final container = containerFor(
        MemoryStorage({StorageKeys.accent: saved}),
      );
      addTearDown(container.dispose);
      await container.read(accentProvider.notifier).load();
      expect(container.read(accentProvider), AppPalette.defaultAccent);
    }
  });

  test('setAccent changes the state and persists the ARGB int', () async {
    final storage = MemoryStorage();
    final container = containerFor(storage);
    addTearDown(container.dispose);

    await container.read(accentProvider.notifier).setAccent(blue);

    expect(container.read(accentProvider), blue);
    expect(storage.values[StorageKeys.accent], '${blue.toARGB32()}');
  });

  test('setAccent sends the ARGB int to native', () async {
    final container = containerFor(MemoryStorage());
    addTearDown(container.dispose);

    await container.read(accentProvider.notifier).setAccent(blue);

    verify(() => host.setAccentColor(blue.toARGB32())).called(1);
  });

  test(
    'a throwing native call is logged and the accent still changes',
    () async {
      final lines = <String>[];
      AppLogger.overrideForTesting(sink: (_, message, _) => lines.add(message));
      when(
        () => host.setAccentColor(any()),
      ).thenThrow(PlatformException(code: 'channel-error'));
      final storage = MemoryStorage();
      final container = containerFor(storage);
      addTearDown(container.dispose);

      await container.read(accentProvider.notifier).setAccent(blue);

      expect(container.read(accentProvider), blue);
      expect(storage.values[StorageKeys.accent], '${blue.toARGB32()}');
      expect(lines.single, startsWith('Could not send the accent to native'));
    },
  );

  test('a native call that fails later is logged too', () async {
    final lines = <String>[];
    AppLogger.overrideForTesting(sink: (_, message, _) => lines.add(message));
    when(
      () => host.setAccentColor(any()),
    ).thenAnswer((_) async => throw PlatformException(code: 'channel-error'));
    final container = containerFor(MemoryStorage());
    addTearDown(container.dispose);

    await container.read(accentProvider.notifier).setAccent(blue);

    expect(container.read(accentProvider), blue);
    expect(lines.single, startsWith('Could not send the accent to native'));
  });

  test('sendToNative sends the accent that load restored', () async {
    final container = containerFor(
      MemoryStorage({StorageKeys.accent: '${blue.toARGB32()}'}),
    );
    addTearDown(container.dispose);
    final notifier = container.read(accentProvider.notifier);

    await notifier.load();
    verifyNever(() => host.setAccentColor(any()));
    await notifier.sendToNative();

    verify(() => host.setAccentColor(blue.toARGB32())).called(1);
  });

  test('sendToNative sends the default accent when nothing is saved', () async {
    final container = containerFor(MemoryStorage());
    addTearDown(container.dispose);

    await container.read(accentProvider.notifier).sendToNative();

    verify(
      () => host.setAccentColor(AppPalette.defaultAccent.toARGB32()),
    ).called(1);
  });

  test('a failing storage never throws and the accent still changes', () async {
    AppLogger.overrideForTesting(sink: (_, _, _) {});
    final container = containerFor(ThrowingStorage());
    addTearDown(container.dispose);
    final notifier = container.read(accentProvider.notifier);

    await notifier.load();
    await notifier.setAccent(blue);

    expect(container.read(accentProvider), blue);
  });

  test('load after dispose changes nothing and logs nothing', () async {
    final lines = <String>[];
    AppLogger.overrideForTesting(sink: (_, message, _) => lines.add(message));
    final container = containerFor(
      MemoryStorage({StorageKeys.accent: '${blue.toARGB32()}'}),
    );
    final notifier = container.read(accentProvider.notifier);

    final loading = notifier.load();
    container.dispose();
    await loading;

    expect(lines, isEmpty);
  });
}
