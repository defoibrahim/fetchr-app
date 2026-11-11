import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/services/permissions/notification_permission.dart';
import 'package:permission_handler/permission_handler.dart';

// The plugin's wire values: denied 0, granted 1, permanently denied 4.
const _denied = 0;
const _granted = 1;
const _permanentlyDenied = 4;

const _channel = MethodChannel('flutter.baseflow.com/permissions/methods');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final calls = <MethodCall>[];

  void answer(Object? Function(MethodCall call) reply) {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          calls.add(call);
          return reply(call);
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, null),
    );
  }

  const permission = NotificationPermission();

  test('status asks about the notification permission', () async {
    answer((_) => _permanentlyDenied);

    expect(await permission.status(), PermissionStatus.permanentlyDenied);
    expect(calls.single.method, 'checkPermissionStatus');
    expect(calls.single.arguments, Permission.notification.value);
  });

  test('request asks only for notifications and gives their answer', () async {
    answer((call) => {Permission.notification.value: _granted});

    expect(await permission.request(), PermissionStatus.granted);
    expect(calls.single.method, 'requestPermissions');
    expect(calls.single.arguments, [Permission.notification.value]);
  });

  test('a denied request is reported as denied', () async {
    answer((call) => {Permission.notification.value: _denied});

    expect(await permission.request(), PermissionStatus.denied);
  });

  test('openSettings reports whether the settings page opened', () async {
    answer((_) => true);
    expect(await permission.openSettings(), isTrue);
    expect(calls.single.method, 'openAppSettings');

    answer((_) => null);
    expect(await permission.openSettings(), isFalse);
  });
}
