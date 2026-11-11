import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/app/shared/domain/entities/quality.dart';
import 'package:grabby/core/utils/formatters.dart';
import 'package:grabby/modules/downloader/domain/entities/format_option.dart';
import 'package:grabby/modules/downloader/presentation/formatters/format_option_formatter.dart';

import '../../../../support/fixtures.dart';

void main() {
  group('detail', () {
    group('best', () {
      test('gives the short side and the dimensions', () {
        expect(
          (const FormatOption(
            quality: Quality.best,
            width: 3840,
            height: 2160,
          )).detail,
          '2160p · 3840×2160',
        );
      });

      test('takes the short side of a portrait clip', () {
        expect(
          (const FormatOption(
            quality: Quality.best,
            width: 1080,
            height: 1920,
          )).detail,
          '1080p · 1080×1920',
        );
      });

      test('falls back without both dimensions', () {
        const fallback = 'Video + audio merged';
        expect((const FormatOption(quality: Quality.best)).detail, fallback);
        expect(
          (const FormatOption(quality: Quality.best, width: 1920)).detail,
          fallback,
        );
      });
    });

    group('1080p and 720p', () {
      test('list the dimensions and the frame rate', () {
        expect(
          (const FormatOption(
            quality: Quality.p1080,
            width: 1920,
            height: 1080,
            fps: 30,
          )).detail,
          'MP4 · 1920×1080 · 30 fps',
        );
        expect(
          (const FormatOption(
            quality: Quality.p720,
            width: 1280,
            height: 720,
            fps: 24,
          )).detail,
          'MP4 · 1280×720 · 24 fps',
        );
      });

      test('round the frame rate', () {
        expect(
          (const FormatOption(quality: Quality.p720, fps: 59.94)).detail,
          'MP4 · 60 fps',
        );
      });

      test('leave out what is not known', () {
        expect(
          (const FormatOption(
            quality: Quality.p1080,
            width: 1920,
            height: 1080,
          )).detail,
          'MP4 · 1920×1080',
        );
        expect(
          (const FormatOption(quality: Quality.p720, fps: 30)).detail,
          'MP4 · 30 fps',
        );
        expect(
          (const FormatOption(quality: Quality.p1080, width: 1920)).detail,
          'MP4',
        );
      });

      test('fall back to MP4', () {
        expect((const FormatOption(quality: Quality.p1080)).detail, 'MP4');
        expect((const FormatOption(quality: Quality.p720)).detail, 'MP4');
      });

      test('treat a zero frame rate as unknown', () {
        expect(
          (const FormatOption(quality: Quality.p720, fps: 0)).detail,
          'MP4',
        );
      });
    });

    group('480p', () {
      test('lists what is known like the others', () {
        expect(
          (const FormatOption(
            quality: Quality.p480,
            width: 854,
            height: 480,
            fps: 30,
          )).detail,
          'MP4 · 854×480 · 30 fps',
        );
      });

      test('falls back to the data saver line', () {
        expect(
          (const FormatOption(quality: Quality.p480)).detail,
          'MP4 · data saver',
        );
      });
    });

    test('mp3 is the same with or without data', () {
      const text = 'MP3 · best quality (VBR)';
      expect((const FormatOption(quality: Quality.mp3)).detail, text);
      expect(
        (const FormatOption(
          quality: Quality.mp3,
          width: 1,
          height: 1,
          sizeBytes: 5,
        )).detail,
        text,
      );
    });

    group('cover', () {
      test('gives the dimensions', () {
        expect(
          (const FormatOption(
            quality: Quality.cover,
            width: 1280,
            height: 720,
          )).detail,
          'JPEG · 1280×720',
        );
      });

      test('falls back to JPEG', () {
        expect((const FormatOption(quality: Quality.cover)).detail, 'JPEG');
      });
    });
  });

  group('sizeText', () {
    test('is the size of an exact option', () {
      expect(
        (const FormatOption(quality: Quality.p720, sizeBytes: gb)).sizeText,
        formatBytes(gb),
      );
    });

    test('has no prefix on an exact size', () {
      expect(
        (const FormatOption(quality: Quality.p720, sizeBytes: gb)).sizeText,
        isNot(startsWith('~')),
      );
    });

    test('marks an estimate with a tilde', () {
      expect(
        (const FormatOption(
          quality: Quality.best,
          sizeBytes: 3 * gb ~/ 2,
          sizeIsEstimate: true,
        )).sizeText,
        '~1.5 GB',
      );
    });

    test('says so when there is no size', () {
      expect(
        (const FormatOption(quality: Quality.cover)).sizeText,
        'size unknown',
      );
      expect(
        (const FormatOption(
          quality: Quality.mp3,
          sizeIsEstimate: true,
        )).sizeText,
        'size unknown',
      );
    });
  });
}
