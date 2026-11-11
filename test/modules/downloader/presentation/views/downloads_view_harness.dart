import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:grabby/app/routes/app_routes.dart';
import 'package:grabby/app/shared/notification_permission_provider.dart';
import 'package:grabby/core/errors/result.dart';
import 'package:grabby/core/theme/theme.dart';
import 'package:grabby/core/utils/scale.dart';
import 'package:grabby/modules/downloader/di/downloader_providers.dart';
import 'package:grabby/modules/downloader/domain/entities/download_task.dart';
import 'package:grabby/modules/downloader/presentation/views/downloads_view.dart';
import 'package:mocktail/mocktail.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../core/widgets/widget_harness.dart';
import '../../../../support/fixtures.dart';
import '../../../../support/mocks.dart';

late StreamController<List<DownloadTask>> events;
late MockWatchDownloadsUseCase watch;
late MockCancelDownloadUseCase cancel;
late MockRetryDownloadUseCase retry;
late MockPauseDownloadUseCase pause;
late MockResumeDownloadUseCase resume;
late MockRemoveDownloadUseCase remove;
late MockOpenDownloadFolderUseCase openFolder;
late MockNotificationPermission permission;

Future<Result<void>> _ok(Invocation _) async => const Ok<void>(null);

void setUpDownloadsHarness() {
  events = StreamController<List<DownloadTask>>();
  // close() on a controller nobody listened to never completes, which would
  // hang a test that pumps a row without the view.
  addTearDown(() => unawaited(events.close()));
  watch = MockWatchDownloadsUseCase();
  when(() => watch()).thenAnswer((_) => events.stream);
  cancel = MockCancelDownloadUseCase();
  retry = MockRetryDownloadUseCase();
  pause = MockPauseDownloadUseCase();
  resume = MockResumeDownloadUseCase();
  remove = MockRemoveDownloadUseCase();
  openFolder = MockOpenDownloadFolderUseCase();
  permission = MockNotificationPermission();
  when(() => cancel(any())).thenAnswer(_ok);
  when(() => retry(any())).thenAnswer(_ok);
  when(() => pause(any())).thenAnswer(_ok);
  when(() => resume(any())).thenAnswer(_ok);
  when(() => openFolder(any())).thenAnswer(_ok);
  when(() => remove(any())).thenAnswer((_) async => const Ok(true));
  when(
    () => permission.status(),
  ).thenAnswer((_) async => PermissionStatus.granted);
  when(
    () => permission.request(),
  ).thenAnswer((_) async => PermissionStatus.granted);
  when(() => permission.openSettings()).thenAnswer((_) async => true);
}

Future<void> pumpView(WidgetTester tester, {Size size = designSize}) async {
  useView(tester, size);
  final router = GoRouter(
    initialLocation: AppRoutes.downloads,
    routes: [
      GoRoute(
        path: AppRoutes.downloads,
        builder: (_, _) => const DownloadsView(),
      ),
      GoRoute(path: AppRoutes.home, builder: (_, _) => const Text('home')),
      GoRoute(
        path: AppRoutes.player,
        builder: (_, state) => Text(
          'player ${state.uri.queryParameters['uri']} '
          '${state.uri.queryParameters['title']}',
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        watchDownloadsUseCaseProvider.overrideWithValue(watch),
        cancelDownloadUseCaseProvider.overrideWithValue(cancel),
        retryDownloadUseCaseProvider.overrideWithValue(retry),
        pauseDownloadUseCaseProvider.overrideWithValue(pause),
        resumeDownloadUseCaseProvider.overrideWithValue(resume),
        removeDownloadUseCaseProvider.overrideWithValue(remove),
        openDownloadFolderUseCaseProvider.overrideWithValue(openFolder),
        notificationPermissionProvider.overrideWithValue(permission),
      ],
      child: ScaleScope(
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: router,
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> emit(WidgetTester tester, List<DownloadTask> tasks) async {
  events.add(tasks);
  await tester.pump();
  await tester.pump();
}

Future<void> pumpWith(
  WidgetTester tester,
  List<DownloadTask> tasks, {
  Size size = designSize,
}) async {
  await pumpView(tester, size: size);
  await emit(tester, tasks);
}

DownloadTask running([String id = 'a']) => downloadTask(
  id: id,
  stage: TaskStage.downloading,
  progress: .64,
  downloadedBytes: 118 * mb,
  totalBytes: 184 * mb,
  speed: mb,
  etaSec: 60,
);

DownloadTask done([String id = 'd', String? savedUri, String? title]) =>
    downloadTask(
      id: id,
      status: TaskStatus.completed,
      savedUri: savedUri ?? 'content://media/$id',
      finishedAt: DateTime.now(),
      totalBytes: 96 * mb,
      request: title == null
          ? null
          : downloadRequest(url: 'https://example.com/$id', title: title),
    );

DownloadTask failed(String id, {String? code, String? message}) => downloadTask(
  id: id,
  status: TaskStatus.failed,
  errorCode: code ?? 'network',
  errorMessage: message,
  progress: .41,
);
