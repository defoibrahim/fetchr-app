import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/app/shared/domain/entities/quality.dart';
import 'package:grabby/modules/downloader/domain/entities/format_option.dart';

import '../../../support/fixtures.dart';

void main() {
  group('MediaInfo.pick', () {
    test('keeps the preferred quality when the source offers it', () {
      final info = mediaInfo(
        options: formatOptions([Quality.best, Quality.p720, Quality.mp3]),
      );

      expect(info.pick(Quality.p720).quality, Quality.p720);
    });

    test('returns the offered option itself, with its details', () {
      const sized = FormatOption(quality: Quality.p720, sizeBytes: 2000);
      final info = mediaInfo(
        options: [
          const FormatOption(quality: Quality.best),
          sized,
        ],
      );

      expect(info.pick(Quality.p720), sized);
    });

    test('falls back to the first offered option when it does not', () {
      final info = mediaInfo(
        options: formatOptions([Quality.p720, Quality.p480, Quality.mp3]),
      );

      expect(info.pick(Quality.p1080).quality, Quality.p720);
    });

    test('an audio-only source falls back to MP3', () {
      final info = mediaInfo(options: formatOptions([Quality.mp3]));

      expect(info.pick(Quality.best).quality, Quality.mp3);
    });
  });

  group('MediaInfo.optionFor and optionBelow', () {
    final info = mediaInfo(
      options: formatOptions([Quality.p720, Quality.p480, Quality.mp3]),
    );

    test('optionFor finds the offered quality, or null', () {
      expect(info.optionFor(Quality.p480)?.quality, Quality.p480);
      expect(info.optionFor(Quality.p1080), isNull);
    });

    test('optionBelow is the next option in the list', () {
      expect(info.optionBelow(Quality.p720)?.quality, Quality.p480);
      expect(info.optionBelow(Quality.p480)?.quality, Quality.mp3);
    });

    test('optionBelow is null past the end or for a quality not offered', () {
      expect(info.optionBelow(Quality.mp3), isNull);
      expect(info.optionBelow(Quality.best), isNull);
    });
  });
}
