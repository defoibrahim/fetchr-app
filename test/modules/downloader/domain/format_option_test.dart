import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/app/shared/domain/entities/quality.dart';
import 'package:grabby/modules/downloader/domain/entities/format_option.dart';

void main() {
  group('shortSide', () {
    test('is the smaller side of a landscape clip', () {
      const option = FormatOption(
        quality: Quality.p1080,
        width: 1920,
        height: 1080,
      );

      expect(option.shortSide, 1080);
    });

    test('is the same for a portrait clip', () {
      const option = FormatOption(
        quality: Quality.p1080,
        width: 1080,
        height: 1920,
      );

      expect(option.shortSide, 1080);
    });

    test('is unknown unless both sides are', () {
      expect(const FormatOption(quality: Quality.best).shortSide, isNull);
      expect(
        const FormatOption(quality: Quality.best, width: 1920).shortSide,
        isNull,
      );
      expect(
        const FormatOption(quality: Quality.best, height: 1080).shortSide,
        isNull,
      );
    });
  });

  test('compares by value', () {
    expect(
      const FormatOption(quality: Quality.p720, sizeBytes: 5),
      const FormatOption(quality: Quality.p720, sizeBytes: 5),
    );
    expect(
      const FormatOption(quality: Quality.p720, sizeBytes: 5),
      isNot(
        const FormatOption(
          quality: Quality.p720,
          sizeBytes: 5,
          sizeIsEstimate: true,
        ),
      ),
    );
  });
}
