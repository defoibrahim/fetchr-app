import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/utils/formatters.dart';
import 'package:grabby/modules/library/presentation/formatters/library_item_formatter.dart';

import '../../../../support/fixtures.dart';

void main() {
  group('qualityLabel', () {
    test('is the short side, so a landscape and a portrait clip agree', () {
      expect(libraryItem(width: 1920, height: 1080).qualityLabel, '1080p');
      expect(libraryItem(width: 1080, height: 1920).qualityLabel, '1080p');
      expect(libraryItem(width: 1280, height: 720).qualityLabel, '720p');
    });

    test('audio is MP3, whatever the dimensions say', () {
      expect(
        libraryItem(isAudio: true, mimeType: 'audio/mpeg').qualityLabel,
        'MP3',
      );
      expect(
        libraryItem(isAudio: true, width: 640, height: 480).qualityLabel,
        'MP3',
      );
    });

    test('a video with no dimensions is just Video', () {
      expect(libraryItem().qualityLabel, 'Video');
    });

    test('one known side is not enough', () {
      expect(libraryItem(width: 1920).qualityLabel, 'Video');
      expect(libraryItem(height: 1080).qualityLabel, 'Video');
    });
  });

  group('metaText', () {
    test('joins the quality and the size', () {
      final item = libraryItem(width: 1920, height: 1080, sizeBytes: 5452595);
      expect(item.metaText, '1080p · ${formatBytes(5452595)}');
    });

    test('an audio file reads MP3 and its size', () {
      final item = libraryItem(isAudio: true, sizeBytes: 6501171);
      expect(item.metaText, 'MP3 · 6.2 MB');
    });

    test('a video of unknown quality still shows its size', () {
      expect(libraryItem(sizeBytes: 1048576).metaText, 'Video · 1.0 MB');
    });
  });

  group('containerLabel', () {
    test('is the upper-cased file extension', () {
      expect(libraryItem(name: 'Clip.mp4').containerLabel, 'MP4');
      expect(
        libraryItem(name: 'Song.mp3', isAudio: true).containerLabel,
        'MP3',
      );
    });

    test('uses the last dot of a name that has several', () {
      expect(libraryItem(name: 'a.b.c.webm').containerLabel, 'WEBM');
    });

    test('falls back to the mime subtype when the name has no extension', () {
      expect(
        libraryItem(name: 'Clip', mimeType: 'video/mp4').containerLabel,
        'MP4',
      );
    });
  });

  group('formatLabel', () {
    test('is the quality and the container', () {
      final item = libraryItem(width: 1920, height: 1080, name: 'Clip.mp4');
      expect(item.formatLabel, '1080p · MP4');
    });

    test('says MP3 once for an audio file', () {
      final item = libraryItem(name: 'Song.mp3', isAudio: true);
      expect(item.formatLabel, 'MP3');
    });
  });

  group('location', () {
    test('joins the folder and the name', () {
      final item = libraryItem(
        name: 'Desert drive.mp4',
        relativePath: 'Movies/Fetchr/',
      );
      expect(item.location, 'Movies/Fetchr/Desert drive.mp4');
    });

    test('adds the slash a folder without one is missing', () {
      final item = libraryItem(name: 'Song.mp3', relativePath: 'Music/Fetchr');
      expect(item.location, 'Music/Fetchr/Song.mp3');
    });

    test('is just the name when the folder is unknown or empty', () {
      expect(libraryItem(name: 'Clip.mp4').location, 'Clip.mp4');
      expect(
        libraryItem(name: 'Clip.mp4', relativePath: '').location,
        'Clip.mp4',
      );
    });
  });
}
