import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/app/shared/domain/entities/quality.dart';
import 'package:grabby/core/errors/result.dart';
import 'package:grabby/modules/downloader/domain/entities/download_task.dart';
import 'package:grabby/modules/downloader/domain/entities/format_option.dart';
import 'package:grabby/modules/downloader/domain/entities/media_info.dart';

import '../modules/downloader/presentation/views/home_view_support.dart';
import '../support/fake_app.dart';
import '../support/fixtures.dart';

/// Wraps to many lines at any width.
final longTitle = 'A very long title that never fits on one line ' * 4;

const _link = 'https://www.youtube.com/watch?v=Qx7mT0aK3pE';

/// 64% through a 184 MB file: the card the Downloads tab shows for it.
DownloadTask runningTask({String id = 'a', String? title}) => downloadTask(
  id: id,
  stage: TaskStage.downloading,
  progress: .64,
  downloadedBytes: 118 * mb,
  totalBytes: 184 * mb,
  speed: (4.2 * mb).round(),
  etaSec: 16,
  request: downloadRequest(
    url: 'https://example.com/$id',
    title: title ?? 'Desert drive at golden hour',
  ),
);

/// Finished today, so Home lists it under Recent and Downloads under Done.
DownloadTask doneTask(String id, {String? title}) => downloadTask(
  id: id,
  status: TaskStatus.completed,
  savedUri: 'content://media/$id',
  finishedAt: DateTime.now(),
  totalBytes: 96 * mb,
  request: downloadRequest(
    url: 'https://example.com/$id',
    title: title ?? 'Video $id',
  ),
);

/// One video with every quality the picker can offer.
MediaInfo richVideo({String title = 'Desert drive at golden hour'}) =>
    mediaInfo(
      url: _link,
      title: title,
      uploader: 'Open Road Films',
      durationSec: 3725,
      thumbnail: 'https://example.com/t.jpg',
      options: [
        for (final quality in Quality.values)
          FormatOption(
            quality: quality,
            width: quality.isAudio ? null : 1920,
            height: quality.isAudio ? null : 1080,
            fps: quality.isAudio ? null : 60,
            sizeBytes: 184 * mb,
            sizeIsEstimate: true,
          ),
      ],
    );

MediaInfo playlistOf(int entries, {String? title}) => mediaInfo(
  url: 'https://www.youtube.com/playlist?list=PL1',
  title: title ?? 'Coastal road trips',
  isPlaylist: true,
  options: formatOptions([
    Quality.best,
    Quality.p1080,
    Quality.p720,
    Quality.p480,
    Quality.mp3,
  ]),
  entries: [
    for (var i = 1; i <= entries; i++)
      PlaylistEntry(
        url: 'https://example.com/v/$i',
        title: 'Entry $i',
        durationSec: i * 60,
      ),
  ],
);

/// The routed app on [size] with a link typed and Get formats tapped, so the
/// picker is open when [info] fetches. The text scale and the view are the
/// caller's to set first.
Future<FakeApp> pumpOpenSheet(
  WidgetTester tester,
  Size size, {
  MediaInfo? info,
  ThemeData? theme,
}) async {
  final app = homeApp();
  stubFetch(app, Ok(info ?? clipInfo));
  await pumpFakeApp(tester, app: app, size: size, theme: theme);
  await typeUrl(tester, clipUrl);
  await getFormats(tester);
  return app;
}

/// A widget test with semantics on. The handle is released before the tester
/// checks for leaks, which a `addTearDown` would run too late for.
void semanticsTest(
  String description,
  Future<void> Function(WidgetTester tester) body,
) => testWidgets(description, (tester) async {
  final handle = tester.ensureSemantics();
  try {
    await body(tester);
  } finally {
    handle.dispose();
  }
});

/// The smallest rect holding every match of [finder].
Rect spanOf(WidgetTester tester, Finder finder) {
  final count = finder.evaluate().length;
  expect(count, greaterThan(0), reason: 'nothing matches $finder');
  return [
    for (var i = 0; i < count; i++) tester.getRect(finder.at(i)),
  ].reduce((a, b) => a.expandToInclude(b));
}
