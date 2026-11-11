import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/app/theme/accent_provider.dart';
import 'package:grabby/modules/downloader/presentation/views/home_view.dart';

import 'fake_app.dart';
import 'mocks.dart';

const _pink = Color(0xFFFF4081);

void main() {
  testWidgets('overrides add providers the mocks do not cover', (tester) async {
    await pumpFakeApp(
      tester,
      overrides: [accentProvider.overrideWith(() => FixedAccent(_pink))],
    );

    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomeView)),
    );
    expect(container.read(accentProvider), _pink);
  });
}
