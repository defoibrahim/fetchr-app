import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/app/shared/formatters/yt_dlp_formatter.dart';
import 'package:grabby/app/shared/yt_dlp_provider.dart';

import '../../../support/fixtures.dart';

void main() {
  final now = DateTime(2026, 10, 15, 9, 30);

  String? idle(DateTime? checkedAt, [DateTime? at]) => ytDlpCaption(
    ytDlpStatus(version: '2026.10.01', checkedAt: checkedAt),
    YtDlpUpdatePhase.idle,
    at ?? now,
  );

  group('busy and done ignore the clock', () {
    test('busy says it is downloading', () {
      expect(
        ytDlpCaption(
          ytDlpStatus(checkedAt: DateTime(2020)),
          YtDlpUpdatePhase.busy,
          now,
        ),
        'Downloading the latest release…',
      );
    });

    test('done says it just updated', () {
      expect(
        ytDlpCaption(ytDlpStatus(), YtDlpUpdatePhase.done, now),
        'Updated just now',
      );
    });
  });

  group('without a status', () {
    test('idle has no caption, an update still reports itself', () {
      expect(ytDlpCaption(null, YtDlpUpdatePhase.idle, now), isNull);
      expect(
        ytDlpCaption(null, YtDlpUpdatePhase.busy, now),
        'Downloading the latest release…',
      );
    });
  });

  group('labels', () {
    test('the version, or bundled before native reports one', () {
      expect(
        ytDlpStatus(version: '2026.08.19').versionLabel,
        'yt-dlp 2026.08.19',
      );
      expect(ytDlpStatus().versionLabel, 'yt-dlp bundled');
    });

    test('Check again only once an update finished', () {
      expect(YtDlpUpdatePhase.idle.actionLabel, 'Update yt-dlp');
      expect(YtDlpUpdatePhase.busy.actionLabel, 'Update yt-dlp');
      expect(YtDlpUpdatePhase.done.actionLabel, 'Check again');
    });
  });

  group('idle', () {
    test('never checked', () {
      expect(idle(null), 'Never checked');
    });

    test('earlier today, with the time padded', () {
      expect(idle(DateTime(2026, 10, 15, 9, 12)), 'Last checked today, 09:12');
      expect(idle(DateTime(2026, 10, 15, 0, 5)), 'Last checked today, 00:05');
    });

    test('a moment in the future of today still reads today', () {
      expect(idle(DateTime(2026, 10, 15, 23, 59)), 'Last checked today, 23:59');
    });

    test('yesterday, with the time', () {
      expect(
        idle(DateTime(2026, 10, 14, 9, 12)),
        'Last checked yesterday, 09:12',
      );
    });

    test('two days ago is a date', () {
      expect(idle(DateTime(2026, 10, 13, 23, 59)), 'Last checked 13 Oct');
    });

    test('a date has no zero padding on the day', () {
      expect(idle(DateTime(2026, 9, 3, 8)), 'Last checked 3 Sep');
    });

    test('names every month', () {
      const names = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      for (var month = 1; month <= 12; month++) {
        expect(
          idle(DateTime(2025, month, 12, 9)),
          'Last checked 12 ${names[month - 1]}',
        );
      }
    });
  });

  group('midnight boundaries', () {
    test('one minute after midnight, 23:59 the day before is yesterday', () {
      final justAfter = DateTime(2026, 10, 15, 0, 1);

      expect(
        idle(DateTime(2026, 10, 14, 23, 59), justAfter),
        'Last checked yesterday, 23:59',
      );
      expect(
        idle(DateTime(2026, 10, 15), justAfter),
        'Last checked today, 00:00',
      );
    });

    test('one minute before midnight, 00:00 the day before is yesterday', () {
      final justBefore = DateTime(2026, 10, 15, 23, 59);

      expect(
        idle(DateTime(2026, 10, 14), justBefore),
        'Last checked yesterday, 00:00',
      );
      expect(
        idle(DateTime(2026, 10, 13, 23, 59), justBefore),
        'Last checked 13 Oct',
      );
    });

    test('the first of a month looks back to the last of the previous', () {
      final firstOfMonth = DateTime(2026, 11, 1, 0, 30);

      expect(
        idle(DateTime(2026, 10, 31, 23, 50), firstOfMonth),
        'Last checked yesterday, 23:50',
      );
      expect(
        idle(DateTime(2026, 10, 30, 23, 50), firstOfMonth),
        'Last checked 30 Oct',
      );
    });

    test('the first of a year looks back to the 31st of December', () {
      final newYear = DateTime(2027, 1, 1, 0, 10);

      expect(
        idle(DateTime(2026, 12, 31, 22, 0), newYear),
        'Last checked yesterday, 22:00',
      );
    });

    test('the first of March after a leap day counts 29 February', () {
      final march = DateTime(2028, 3, 1, 8);

      expect(
        idle(DateTime(2028, 2, 29, 8), march),
        'Last checked yesterday, 08:00',
      );
    });
  });
}
