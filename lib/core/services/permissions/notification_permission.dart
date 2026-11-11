import 'package:permission_handler/permission_handler.dart';

/// The notification permission (Android 13+), behind a class a test can mock.
///
/// On Android `status()` never reports `permanentlyDenied`: it is only the
/// answer to a `request()` that showed no dialog, so a caller that gets it
/// back sends the user to `openSettings()`.
class NotificationPermission {
  const NotificationPermission();

  Future<PermissionStatus> status() => Permission.notification.status;

  Future<PermissionStatus> request() => Permission.notification.request();

  Future<bool> openSettings() => openAppSettings();
}
