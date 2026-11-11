import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/widgets/app_snackbar.dart';

/// The Undo snackbar slides in first; its timer starts when that has finished.
Future<void> pumpSnackbarIn(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 750));
}

/// Runs out the Undo window and lets the commit and the exit animation finish.
Future<void> pumpUndoExpired(WidgetTester tester) async {
  await tester.pump(AppSnackbar.undoDuration);
  await tester.pumpAndSettle();
}
