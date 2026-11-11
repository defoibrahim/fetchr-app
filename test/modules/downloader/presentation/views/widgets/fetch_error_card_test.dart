import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/app/shared/yt_dlp_provider.dart';
import 'package:grabby/core/errors/failure.dart';
import 'package:grabby/core/gen/assets.gen.dart';
import 'package:grabby/core/gen/fonts.gen.dart';
import 'package:grabby/core/utils/formatters.dart';
import 'package:grabby/core/widgets/app_button.dart';
import 'package:grabby/core/widgets/error_card.dart';
import 'package:grabby/modules/downloader/presentation/views/widgets/fetch_error_card.dart';

import '../../../../../core/widgets/widget_harness.dart';

void main() {
  final calls = <String>[];

  setUp(calls.clear);

  FetchErrorActions actions() => FetchErrorActions(
    updateYtDlp: () => calls.add('update'),
    editLink: () => calls.add('edit'),
    anotherLink: () => calls.add('another'),
    retry: () => calls.add('retry'),
    lowerQuality: () => calls.add('lower'),
    openLibrary: () => calls.add('library'),
  );

  ErrorCardData card(
    Failure failure, {
    ({int needed, int free})? storage,
    YtDlpUpdatePhase phase = YtDlpUpdatePhase.idle,
  }) => fetchErrorCard(
    failure,
    actions: actions(),
    storage: storage,
    ytDlpPhase: phase,
  );

  String bodyOf(ErrorCardData data) =>
      TextSpan(children: data.body).toPlainText();

  List<String> labels(ErrorCardData data) => [
    for (final action in data.actions) action.label,
  ];

  group('copy', () {
    final cases =
        <
          ({
            String name,
            Failure failure,
            String title,
            String body,
            List<String> actions,
          })
        >[
          (
            name: 'unsupported site',
            failure: const UnsupportedSiteFailure(),
            title: "This site isn't supported",
            body:
                "yt-dlp couldn't find a video at this link. Check the URL, or update yt-dlp — support for new sites lands often.",
            actions: ['Update yt-dlp', 'Edit link'],
          ),
          (
            name: 'private video',
            failure: const PrivateVideoFailure(),
            title: 'This video is private',
            body:
                "Only people the uploader approved can watch it, so Fetchr can't download it.",
            actions: ['Try another link'],
          ),
          (
            name: 'network',
            failure: const NetworkFailure(),
            title: 'No internet connection',
            body:
                'Connect to Wi-Fi or mobile data and try again. Downloads already running will resume on their own.',
            actions: ['Retry'],
          ),
          (
            name: 'unavailable',
            failure: const MediaUnavailableFailure(),
            title: "This video isn't available",
            body: "It may have been removed, or it's blocked where you are.",
            actions: ['Try another link'],
          ),
          (
            name: 'busy',
            failure: const YtDlpBusyFailure(),
            title: 'yt-dlp is updating',
            body: 'Try again in a moment.',
            actions: ['Retry'],
          ),
          (
            name: 'unknown',
            failure: const UnexpectedFailure(),
            title: "Couldn't get this video",
            body: 'yt-dlp reported an error. Updating it often helps.',
            actions: ['Update yt-dlp', 'Edit link'],
          ),
        ];

    for (final c in cases) {
      test('${c.name}: title, body and actions', () {
        final data = card(c.failure);

        expect(data.title, c.title);
        expect(bodyOf(data), c.body);
        expect(labels(data), c.actions);
      });
    }

    test('storage: the sizes in the body and Lower quality first', () {
      final data = card(
        const StorageFailure(),
        storage: (needed: 1288490189, free: 671088640),
      );

      expect(data.title, 'Not enough storage');
      expect(
        bodyOf(data),
        'This download needs about ${formatBytes(1288490189)} and '
        '${formatBytes(671088640)} is free. Pick a lower quality or clear '
        'some space.',
      );
      expect(labels(data), ['Lower quality', 'Open Library']);
    });

    test('storage: the two sizes are set in the mono family', () {
      final data = card(
        const StorageFailure(),
        storage: (needed: 1288490189, free: 671088640),
      );

      final mono = [
        for (final span in data.body)
          if (span is TextSpan &&
              span.style?.fontFamily == FontFamily.jetBrainsMono)
            span.text,
      ];
      expect(mono, [formatBytes(1288490189), formatBytes(671088640)]);
    });

    test('the storage data wins over the failure type', () {
      final data = card(
        const UnexpectedFailure(),
        storage: (needed: 100, free: 50),
      );

      expect(data.title, 'Not enough storage');
    });
  });

  group('icons', () {
    test('each card has its own glyph', () {
      expect(
        card(const UnsupportedSiteFailure()).icon,
        Assets.icons.alertCircle,
      );
      expect(card(const PrivateVideoFailure()).icon, Assets.icons.lock);
      expect(card(const NetworkFailure()).icon, Assets.icons.wifiOff);
      expect(
        card(const StorageFailure(), storage: (needed: 2, free: 1)).icon,
        Assets.icons.hardDrive,
      );
    });
  });

  group('actions', () {
    test('every button calls its own handler', () {
      final cases = <(Failure, ({int needed, int free})?, List<String>)>[
        (const UnsupportedSiteFailure(), null, ['update', 'edit']),
        (const UnexpectedFailure(), null, ['update', 'edit']),
        (const PrivateVideoFailure(), null, ['another']),
        (const MediaUnavailableFailure(), null, ['another']),
        (const NetworkFailure(), null, ['retry']),
        (const YtDlpBusyFailure(), null, ['retry']),
        (const StorageFailure(), (needed: 2, free: 1), ['lower', 'library']),
      ];

      for (final (failure, storage, expected) in cases) {
        calls.clear();
        for (final action in card(failure, storage: storage).actions) {
          action.onPressed();
        }
        expect(calls, expected, reason: '$failure');
      }
    });

    test('the first action is the primary one when the card has two', () {
      expect(
        [
          for (final a in card(const UnsupportedSiteFailure()).actions)
            a.primary,
        ],
        [true, false],
      );
      expect(card(const NetworkFailure()).actions.single.primary, isTrue);
      expect(card(const PrivateVideoFailure()).actions.single.primary, isFalse);
    });

    test('Update yt-dlp follows the shared phase', () {
      final idle = card(const UnsupportedSiteFailure()).actions.first;
      expect((idle.label, idle.busy), ('Update yt-dlp', false));

      final busy = card(
        const UnsupportedSiteFailure(),
        phase: YtDlpUpdatePhase.busy,
      ).actions.first;
      expect(
        (busy.label, busy.busy, busy.busyLabel),
        ('Update yt-dlp', true, 'Updating…'),
      );

      final done = card(
        const UnsupportedSiteFailure(),
        phase: YtDlpUpdatePhase.done,
      ).actions.first;
      expect((done.label, done.busy), ('Check again', false));
      done.onPressed();
      expect(calls, ['update']);
    });

    test('the unknown card follows the phase too', () {
      final busy = card(
        const UnexpectedFailure(),
        phase: YtDlpUpdatePhase.busy,
      ).actions.first;
      expect(busy.busy, isTrue);
    });
  });

  group('rendered', () {
    testWidgets('the buttons are tappable, except while updating', (
      tester,
    ) async {
      await pumpThemed(
        tester,
        SingleChildScrollView(
          child: ErrorCard(data: card(const UnsupportedSiteFailure())),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));

      await tester.tap(find.text('Edit link'));
      await tester.tap(find.text('Update yt-dlp'));
      expect(calls, ['edit', 'update']);

      calls.clear();
      await tester.pumpWidget(
        themed(
          SingleChildScrollView(
            child: ErrorCard(
              data: card(
                const UnsupportedSiteFailure(),
                phase: YtDlpUpdatePhase.busy,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Updating…'), findsOneWidget);
      await tester.tap(find.text('Updating…'));
      expect(calls, isEmpty);
      expect(find.byType(AppButton), findsNWidgets(2));
    });

    testWidgets('the storage card sets the sizes in mono', (tester) async {
      await pumpThemed(
        tester,
        SingleChildScrollView(
          child: ErrorCard(
            data: card(
              const StorageFailure(),
              storage: (needed: 1288490189, free: 671088640),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));

      expect(
        find.textContaining(formatBytes(1288490189), findRichText: true),
        findsOneWidget,
      );
      expect(find.text('Not enough storage'), findsOneWidget);
    });
  });
}
