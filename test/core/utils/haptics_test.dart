import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/utils/haptics.dart';

import '../../support/haptics.dart';

void main() {
  tearDown(() {
    AppHaptics.androidSdk = null;
  });

  testWidgets('each kind plays its feedback', (tester) async {
    final calls = recordHaptics(tester);
    AppHaptics.androidSdk = 34;
    AppHaptics.select();
    AppHaptics.confirm();
    AppHaptics.warn();
    AppHaptics.reject();
    await tester.pump();

    expect(calls, [
      'HapticFeedbackType.selectionClick',
      'HapticFeedbackType.successNotification',
      'HapticFeedbackType.mediumImpact',
      'HapticFeedbackType.errorNotification',
    ]);
  });

  testWidgets('below API 30 confirm and reject fall back to impacts', (
    tester,
  ) async {
    final calls = recordHaptics(tester);
    AppHaptics.androidSdk = 29;
    AppHaptics.confirm();
    AppHaptics.reject();
    await tester.pump();

    expect(calls, [
      'HapticFeedbackType.mediumImpact',
      'HapticFeedbackType.heavyImpact',
    ]);
  });

  testWidgets('the fallback is Android only', (tester) async {
    final calls = recordHaptics(tester);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    AppHaptics.androidSdk = 26;
    AppHaptics.confirm();
    debugDefaultTargetPlatformOverride = null;
    await tester.pump();

    expect(calls, ['HapticFeedbackType.successNotification']);
  });

  testWidgets('a failing channel is swallowed', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (_) async => throw PlatformException(code: 'nope'),
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    AppHaptics.warn();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
