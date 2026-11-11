import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/utils/formatters.dart';

void main() {
  group('formatBytes', () {
    const cases = <int, String>{
      0: '0 B',
      1: '1 B',
      999: '999 B',
      1023: '1023 B',
      1024: '1.0 KB',
      1536: '1.5 KB',
      10240: '10 KB',
      1048576: '1.0 MB',
      5452595: '5.2 MB',
      10444800: '10 MB',
      100663296: '96 MB',
      1073741824: '1.0 GB',
      1288490189: '1.2 GB',
      1610612736: '1.5 GB',
      1099511627776: '1.0 TB',
      // Rounded up to the next unit, never 1024.0 KB or 1024 KB.
      1048575: '1.0 MB',
      1048064: '1.0 MB',
      1073741823: '1.0 GB',
      1125899906842624: '1024 TB',
    };

    for (final MapEntry(key: bytes, value: expected) in cases.entries) {
      test('$bytes is $expected', () {
        expect(formatBytes(bytes), expected);
      });
    }

    test('9.96 MB reads 10 MB, not 10.0 MB', () {
      expect(formatBytes((9.96 * 1024 * 1024).round()), '10 MB');
    });

    test('9.94 MB keeps its decimal', () {
      expect(formatBytes((9.94 * 1024 * 1024).round()), '9.9 MB');
    });

    test('a negative size is 0 B', () {
      expect(formatBytes(-1), '0 B');
      expect(formatBytes(-2048), '0 B');
    });
  });

  group('formatBytesPair', () {
    const mb = 1024 * 1024;

    test('shows both in the total unit', () {
      expect(formatBytesPair(118 * mb, 184 * mb), '118 / 184 MB');
    });

    test('keeps one decimal below 10 in the total unit', () {
      expect(
        formatBytesPair((3.1 * mb).round(), (9.5 * mb).round()),
        '3.1 / 9.5 MB',
      );
    });

    test('a done count under the unit reads as a fraction of it', () {
      expect(
        formatBytesPair(400 * mb, (1.2 * 1024 * mb).round()),
        '0.4 / 1.2 GB',
      );
    });

    test('starts at zero', () {
      expect(formatBytesPair(0, 184 * mb), '0 / 184 MB');
    });

    test('bytes need no decimals', () {
      expect(formatBytesPair(512, 900), '512 / 900 B');
    });

    test('a done count over the total is not clamped', () {
      expect(formatBytesPair(190 * mb, 184 * mb), '190 / 184 MB');
    });

    test('a negative done count is zero', () {
      expect(formatBytesPair(-5, 184 * mb), '0 / 184 MB');
    });
  });

  group('formatSpeed', () {
    test('adds a per-second unit', () {
      expect(formatSpeed((4.2 * 1024 * 1024).round()), '4.2 MB/s');
      expect(formatSpeed(10), '10 B/s');
      expect(formatSpeed(1536), '1.5 KB/s');
    });
  });

  group('formatDuration', () {
    const cases = <int, String>{
      0: '0:00',
      5: '0:05',
      59: '0:59',
      60: '1:00',
      125: '2:05',
      3599: '59:59',
      3600: '1:00:00',
      3661: '1:01:01',
      36000: '10:00:00',
      90061: '25:01:01',
    };

    for (final MapEntry(key: seconds, value: expected) in cases.entries) {
      test('$seconds is $expected', () {
        expect(formatDuration(seconds), expected);
      });
    }

    test('null is empty', () {
      expect(formatDuration(null), '');
    });

    test('a negative duration is empty', () {
      expect(formatDuration(-1), '');
    });
  });

  group('sourceLine', () {
    test('joins the site and the uploader', () {
      expect(
        sourceLine('https://www.youtube.com/watch?v=1', 'Open Road'),
        'youtube.com · Open Road',
      );
    });

    test('is the site alone for a missing or blank uploader', () {
      expect(sourceLine('https://vimeo.com/1', null), 'vimeo.com');
      expect(sourceLine('https://vimeo.com/1', '  '), 'vimeo.com');
    });
  });

  group('plural', () {
    test('one takes no s', () => expect(plural(1, 'video'), '1 video'));
    test('zero and many take an s', () {
      expect(plural(0, 'file'), '0 files');
      expect(plural(17, 'video'), '17 videos');
    });
  });

  group('siteOf', () {
    const cases = <String, String>{
      'https://www.youtube.com/watch?v=x': 'youtube.com',
      'https://m.youtube.com/watch?v=x': 'youtube.com',
      'https://youtu.be/x': 'youtu.be',
      'https://vm.tiktok.com/abc': 'vm.tiktok.com',
      'https://music.example.com/a': 'music.example.com',
      'http://WWW.Example.COM:8080/a': 'example.com',
    };

    for (final MapEntry(key: url, value: expected) in cases.entries) {
      test('$url is $expected', () {
        expect(siteOf(url), expected);
      });
    }

    test('a video converted from the device is This phone', () {
      expect(siteOf('content://media/picker/0/x/media/7'), 'This phone');
      expect(siteOf('file:///storage/emulated/0/Movies/a.mp4'), 'This phone');
    });

    test('a URL with no host gives the input', () {
      expect(siteOf('not a url'), 'not a url');
      expect(siteOf('youtube.com/watch'), 'youtube.com/watch');
      expect(siteOf(''), '');
    });
  });

  group('formatDateTime', () {
    test('is day, English month, year and a 24 hour time', () {
      expect(
        formatDateTime(DateTime(2026, 10, 15, 16, 2)),
        '15 Oct 2026, 16:02',
      );
    });

    test('pads the time but not the day', () {
      expect(formatDateTime(DateTime(2026, 1, 5, 9, 5)), '5 Jan 2026, 09:05');
      expect(
        formatDateTime(DateTime(2026, 12, 31, 0, 0)),
        '31 Dec 2026, 00:00',
      );
    });

    test('shows local time for a UTC date', () {
      final utc = DateTime.utc(2026, 3, 8, 23, 30);
      expect(formatDateTime(utc), formatDateTime(utc.toLocal()));
    });
  });
}
