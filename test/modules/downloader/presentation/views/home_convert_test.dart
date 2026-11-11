import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/app/routes/app_routes.dart';
import 'package:grabby/core/errors/failure.dart';
import 'package:grabby/core/errors/result.dart';
import 'package:mocktail/mocktail.dart';

import 'home_view_support.dart';

const _picked = 'content://media/picker/0/v/7';
final _tile = find.text('Convert a video to MP3');

Future<void> _tapTile(WidgetTester tester) async {
  await tapCard(tester, 'Convert a video to MP3');
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('offers any video on the phone', (tester) async {
    await pumpHome(tester, app: homeApp());

    expect(_tile, findsOneWidget);
    expect(find.text('Pick any video on your phone'), findsOneWidget);
  });

  testWidgets('a picked video is queued as an MP3 in the save folder', (
    tester,
  ) async {
    final app = homeApp();
    when(
      () => app.downloader.pickVideo(),
    ).thenAnswer((_) async => const Ok(_picked));
    when(
      () => app.downloader.convertToMp3(any(), any()),
    ).thenAnswer((_) async => const Ok<void>(null));
    await pumpHome(tester, app: app);

    await _tapTile(tester);

    verify(() => app.downloader.convertToMp3(_picked, 'Fetchr')).called(1);
    expect(find.text('Converting to MP3'), findsOneWidget);
    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();
    expect(locationOf(app), AppRoutes.downloads);
  });

  testWidgets('closing the picker changes nothing', (tester) async {
    final app = homeApp();
    when(
      () => app.downloader.pickVideo(),
    ).thenAnswer((_) async => const Ok<String?>(null));
    await pumpHome(tester, app: app);

    await _tapTile(tester);

    verifyNever(() => app.downloader.convertToMp3(any(), any()));
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a video that cannot be read says so', (tester) async {
    final app = homeApp();
    when(
      () => app.downloader.pickVideo(),
    ).thenAnswer((_) async => const Ok(_picked));
    when(
      () => app.downloader.convertToMp3(any(), any()),
    ).thenAnswer((_) async => const Err<void>(MediaUnavailableFailure()));
    await pumpHome(tester, app: app);

    await _tapTile(tester);

    expect(find.text(const MediaUnavailableFailure().message), findsOneWidget);
  });
}
