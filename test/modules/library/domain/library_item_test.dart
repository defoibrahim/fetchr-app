import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/modules/library/domain/entities/library_item.dart';

LibraryItem _item({int? width, int? height}) => LibraryItem(
  uri: 'content://media/external/video/media/7',
  name: 'Clip.mp4',
  mimeType: 'video/mp4',
  isAudio: false,
  sizeBytes: 1024,
  dateAdded: DateTime.utc(2026),
  width: width,
  height: height,
);

void main() {
  group('LibraryItem.shortSide', () {
    test('is the smaller side, whichever way the clip is turned', () {
      expect(_item(width: 1920, height: 1080).shortSide, 1080);
      expect(_item(width: 1080, height: 1920).shortSide, 1080);
    });

    test('is null unless both sides are known', () {
      expect(_item().shortSide, isNull);
      expect(_item(width: 1920).shortSide, isNull);
      expect(_item(height: 1080).shortSide, isNull);
    });
  });

  test('width and height take part in equality', () {
    expect(_item(width: 1, height: 2), _item(width: 1, height: 2));
    expect(_item(width: 1, height: 2), isNot(_item(width: 1, height: 3)));
  });
}
