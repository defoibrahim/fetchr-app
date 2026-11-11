import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/theme/theme.dart';
import 'package:grabby/modules/downloader/di/downloader_providers.dart';
import 'package:grabby/modules/downloader/domain/entities/download_task.dart';
import 'package:grabby/modules/downloader/presentation/views/widgets/downloads_badge.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../../core/widgets/widget_harness.dart';
import '../../../../../support/fixtures.dart';
import '../../../../../support/mocks.dart';

List<DownloadTask> _tasks(Map<TaskStatus, int> counts) => [
  for (final MapEntry(key: status, value: n) in counts.entries)
    for (var i = 0; i < n; i++) downloadTask(id: '$status$i', status: status),
];

void main() {
  late StreamController<List<DownloadTask>> snapshots;

  setUp(() => snapshots = StreamController<List<DownloadTask>>());
  tearDown(() => snapshots.close());

  Future<void> pumpBadge(
    WidgetTester tester,
    List<DownloadTask> first, {
    Brightness brightness = Brightness.dark,
  }) async {
    final watch = MockWatchDownloadsUseCase();
    when(() => watch()).thenAnswer((_) => snapshots.stream);
    await pumpThemed(
      tester,
      ProviderScope(
        overrides: [watchDownloadsUseCaseProvider.overrideWithValue(watch)],
        child: const DownloadsBadge(),
      ),
      brightness: brightness,
    );
    snapshots.add(first);
    await tester.pumpAndSettle();
  }

  testWidgets('shows nothing until the first snapshot arrives', (tester) async {
    final watch = MockWatchDownloadsUseCase();
    when(() => watch()).thenAnswer((_) => snapshots.stream);
    await pumpThemed(
      tester,
      ProviderScope(
        overrides: [watchDownloadsUseCaseProvider.overrideWithValue(watch)],
        child: const DownloadsBadge(),
      ),
    );

    expect(find.byType(Text), findsNothing);
  });

  testWidgets('counts queued, running and failed tasks', (tester) async {
    await pumpBadge(
      tester,
      _tasks({
        TaskStatus.queued: 1,
        TaskStatus.running: 1,
        TaskStatus.failed: 1,
      }),
    );

    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('counts paused tasks', (tester) async {
    await pumpBadge(tester, _tasks({TaskStatus.paused: 2}));

    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('leaves out completed and cancelled tasks', (tester) async {
    await pumpBadge(
      tester,
      _tasks({
        TaskStatus.running: 1,
        TaskStatus.completed: 4,
        TaskStatus.canceled: 2,
      }),
    );

    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('hides at zero, with or without finished tasks', (tester) async {
    await pumpBadge(tester, const []);
    expect(find.byType(Text), findsNothing);

    snapshots.add(_tasks({TaskStatus.completed: 3, TaskStatus.canceled: 1}));
    await tester.pumpAndSettle();
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('reads 9+ above nine and 9 at nine', (tester) async {
    await pumpBadge(tester, _tasks({TaskStatus.running: 9}));
    expect(find.text('9'), findsOneWidget);

    snapshots.add(_tasks({TaskStatus.running: 10}));
    await tester.pumpAndSettle();
    expect(find.text('9+'), findsOneWidget);

    snapshots.add(
      _tasks({
        TaskStatus.running: 2,
        TaskStatus.queued: 6,
        TaskStatus.failed: 4,
      }),
    );
    await tester.pumpAndSettle();
    expect(find.text('9+'), findsOneWidget);
  });

  testWidgets('follows the tasks as they change', (tester) async {
    await pumpBadge(tester, _tasks({TaskStatus.running: 2}));
    expect(find.text('2'), findsOneWidget);

    snapshots.add(_tasks({TaskStatus.running: 1, TaskStatus.failed: 1}));
    await tester.pumpAndSettle();
    expect(find.text('2'), findsOneWidget);

    snapshots.add(_tasks({TaskStatus.failed: 1}));
    await tester.pumpAndSettle();
    expect(find.text('1'), findsOneWidget);

    snapshots.add(const []);
    await tester.pumpAndSettle();
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('keeps the last count when the stream fails', (tester) async {
    await pumpBadge(tester, _tasks({TaskStatus.running: 2}));

    snapshots.addError(StateError('native is gone'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('2'), findsOneWidget);
  });

  for (final brightness in Brightness.values) {
    testWidgets('is an error-coloured pill with onError text '
        '(${brightness.name})', (tester) async {
      await pumpBadge(
        tester,
        _tasks({TaskStatus.running: 1}),
        brightness: brightness,
      );
      final tokens = AppTokens.of(tester.element(find.byType(DownloadsBadge)));

      final pill = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byType(DownloadsBadge),
          matching: find.byType(DecoratedBox),
        ),
      );
      final decoration = pill.decoration as ShapeDecoration;
      expect(decoration.color, tokens.error);
      expect(decoration.shape, const StadiumBorder());

      final text = tester.widget<Text>(find.text('1'));
      expect(text.style!.color, tokens.onError);
      expect(text.style!.fontWeight, FontWeight.w700);
      expect(text.style!.fontSize, 10);
    });
  }

  testWidgets('is a 16 dp circle for one digit and widens for 9+', (
    tester,
  ) async {
    await pumpBadge(tester, _tasks({TaskStatus.running: 1}));
    final box = find.byType(DownloadsBadge);

    final one = tester.getSize(box);
    expect(one, const Size(16, 16));

    snapshots.add(_tasks({TaskStatus.running: 12}));
    await tester.pumpAndSettle();

    final many = tester.getSize(box);
    expect(many.height, 16);
    expect(many.width, greaterThan(16));
  });
}
