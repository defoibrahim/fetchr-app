import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/theme/theme.dart';
import 'package:grabby/modules/downloader/presentation/views/home_view.dart';

import 'support/fake_app.dart';

void main() {
  for (final (name, theme) in [
    ('light', AppTheme.light()),
    ('dark', AppTheme.dark()),
  ]) {
    testWidgets('every tab renders in the $name theme', (tester) async {
      await pumpFakeApp(tester, theme: theme);

      expect(find.byType(HomeView), findsOneWidget);
      for (final label in ['Downloads', 'Library', 'Settings', 'Home']) {
        await tester.tap(navTab(label));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull, reason: label);
      }
    });
  }
}
