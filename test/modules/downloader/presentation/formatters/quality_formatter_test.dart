import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/app/shared/domain/entities/quality.dart';
import 'package:grabby/modules/downloader/presentation/formatters/quality_formatter.dart';

void main() {
  group('optionLabel', () {
    test('names every quality', () {
      expect(
        [for (final q in Quality.values) q.optionLabel],
        [
          'Best available',
          '1080p',
          '720p',
          '480p',
          'Audio only',
          'Cover photo',
        ],
      );
    });
  });

  group('downloadLabel', () {
    test('uses the pill label', () {
      expect(Quality.p1080.downloadLabel, 'Download 1080p');
      expect(Quality.p720.downloadLabel, 'Download 720p');
      expect(Quality.p480.downloadLabel, 'Download 480p');
      expect(Quality.mp3.downloadLabel, 'Download MP3');
    });

    test('best and cover read lowercase, as the design has them', () {
      expect(Quality.best.downloadLabel, 'Download best');
      expect(Quality.cover.downloadLabel, 'Download cover');
    });
  });

  group('formatLabel', () {
    test('is the quality with its container', () {
      expect(Quality.p1080.formatLabel, '1080p · MP4');
      expect(Quality.mp3.formatLabel, 'MP3');
      expect(Quality.cover.formatLabel, 'Cover · JPG');
    });
  });
}
