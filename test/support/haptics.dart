import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records the haptic calls that reach the platform channel, by their
/// `HapticFeedbackType.*` name, until the test ends. It answers every other
/// platform call with null.
List<String?> recordHaptics(WidgetTester tester) {
  final calls = <String?>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        calls.add(call.arguments as String?);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return calls;
}
