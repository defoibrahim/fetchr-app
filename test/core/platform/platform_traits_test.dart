import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/app/di/core_providers.dart';
import 'package:grabby/core/platform/platform_traits.dart';

void main() {
  group("platform traits keep Android's copy", () {
    test('Android has aria2c, Gallery, no restart and storage access', () {
      const traits = PlatformTraits.android;
      expect(traits.supportsAria2c, isTrue);
      expect(traits.galleryWord, 'Gallery');
      expect(traits.deviceWord, 'phone');
      expect(traits.updateNeedsRestart, isFalse);
      expect(traits.asksStoragePermission, isTrue);
      expect(traits.asksNotificationPermission, isTrue);
      expect(traits.readsClipboardOnResume, isTrue);
      expect(traits.readsAndroidSdk, isTrue);
      expect(PlatformTraits.of(TargetPlatform.android), traits);
    });

    test('a platform Fetchr does not ship on keeps the Android traits', () {
      for (final p in [
        TargetPlatform.fuchsia,
        TargetPlatform.linux,
        TargetPlatform.macOS,
        TargetPlatform.windows,
      ]) {
        expect(PlatformTraits.of(p), PlatformTraits.android, reason: '$p');
      }
    });
  });

  group('iOS traits', () {
    test('iOS has no aria2c, says Files, restarts and asks nothing yet', () {
      const traits = PlatformTraits.ios;
      expect(traits.supportsAria2c, isFalse);
      expect(traits.galleryWord, 'Files');
      expect(traits.deviceWord, 'device');
      expect(traits.updateNeedsRestart, isTrue);
      expect(traits.asksStoragePermission, isFalse);
      expect(traits.asksNotificationPermission, isFalse);
      expect(traits.readsClipboardOnResume, isFalse);
      expect(traits.readsAndroidSdk, isFalse);
      expect(PlatformTraits.of(TargetPlatform.iOS), traits);
    });
  });

  group('platformTraitsProvider', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    for (final (platform, traits) in [
      (TargetPlatform.android, PlatformTraits.android),
      (TargetPlatform.iOS, PlatformTraits.ios),
    ]) {
      test('follows the target platform: ${platform.name}', () {
        debugDefaultTargetPlatformOverride = platform;
        final container = ProviderContainer();
        addTearDown(container.dispose);

        expect(container.read(platformTraitsProvider), traits);
      });
    }
  });
}
