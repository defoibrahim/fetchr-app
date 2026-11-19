import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// What differs between the platforms Fetchr runs on, for presentation to
/// branch on instead of testing the platform itself.
class PlatformTraits extends Equatable {
  const PlatformTraits({
    required this.supportsAria2c,
    required this.galleryWord,
    required this.deviceWord,
    required this.updateNeedsRestart,
    required this.asksStoragePermission,
    required this.asksNotificationPermission,
    required this.readsClipboardOnResume,
    required this.readsAndroidSdk,
    this.nativeLicenseManifest,
  });

  /// Anything but iOS gets Android's traits: Fetchr ships on those two only.
  factory PlatformTraits.of(TargetPlatform platform) =>
      platform == TargetPlatform.iOS ? ios : android;

  static const android = PlatformTraits(
    supportsAria2c: true,
    galleryWord: 'Gallery',
    deviceWord: 'phone',
    updateNeedsRestart: false,
    asksStoragePermission: true,
    asksNotificationPermission: true,
    readsClipboardOnResume: true,
    readsAndroidSdk: true,
  );

  static const ios = PlatformTraits(
    supportsAria2c: false,
    galleryWord: 'Files',
    // Dart cannot tell an iPhone from an iPad without a native call, and the
    // window size is not the idiom (Split View, Stage Manager).
    deviceWord: 'device',
    // Python cannot be re-initialised in-process, so an installed yt-dlp runs
    // from the next launch on.
    updateNeedsRestart: true,
    asksStoragePermission: false,
    // iOS shows its notification prompt once per install; nothing posts one
    // until background downloads (M6) do.
    asksNotificationPermission: false,
    // Reading the pasteboard raises iOS's paste prompt and blocks the main
    // thread until the user answers, so only the Paste tap reads it.
    readsClipboardOnResume: false,
    readsAndroidSdk: false,
    nativeLicenseManifest: 'assets/licenses/ios/manifest.json',
  );

  final bool supportsAria2c;

  /// The app where saved files show up besides Fetchr.
  final String galleryWord;

  /// The device in "your phone" and "This phone".
  final String deviceWord;
  final bool updateNeedsRestart;
  final bool asksStoragePermission;
  final bool asksNotificationPermission;

  /// Whether Home offers a copied link on start and resume.
  final bool readsClipboardOnResume;

  /// Whether the haptics need the Android API level from native.
  final bool readsAndroidSdk;

  /// The licences of what the native layer bundles (tool/ios/collect_licenses.py);
  /// null where the platform lists its own.
  final String? nativeLicenseManifest;

  @override
  List<Object?> get props => [
    supportsAria2c,
    galleryWord,
    deviceWord,
    updateNeedsRestart,
    asksStoragePermission,
    asksNotificationPermission,
    readsClipboardOnResume,
    readsAndroidSdk,
    nativeLicenseManifest,
  ];
}
