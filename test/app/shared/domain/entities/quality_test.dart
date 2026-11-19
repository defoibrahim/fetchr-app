import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/app/shared/domain/entities/quality.dart';

void main() {
  test('only MP3 is audio', () {
    expect(
      [
        for (final q in Quality.values)
          if (q.isAudio) q,
      ],
      [Quality.mp3],
    );
  });

  test('the save path joins the root and the folder', () {
    expect(Quality.p720.savePath('Fetchr'), 'Movies/Fetchr');
    expect(Quality.mp3.savePath('Clips'), 'Music/Clips');
    expect(Quality.cover.savePath('Fetchr'), 'Pictures/Fetchr');
  });

  test('a playlist adds the subfolder native names after it', () {
    String of(String title) => Quality.mp3.savePath('Fetchr', playlist: title);

    expect(of('Road trip'), 'Music/Fetchr/Road trip');
    expect(of('AC/DC: Live'), 'Music/Fetchr/ACDC Live');
    expect(of('../../etc'), 'Music/Fetchr/etc');
    expect(of('a' * 200), 'Music/Fetchr/${'a' * 150}');
    for (final blank in ['', '  ', '..', r'/|\']) {
      expect(of(blank), 'Music/Fetchr', reason: 'for "$blank"');
    }
  });

  test('short labels are the pill texts in settings and the playlist', () {
    expect(Quality.values.map((q) => q.shortLabel), [
      'Best',
      '1080p',
      '720p',
      '480p',
      'MP3',
      'Cover',
    ]);
  });

  test('each quality saves where native MediaKind puts it', () {
    expect(Quality.values.map((q) => q.saveRoot), [
      'Movies',
      'Movies',
      'Movies',
      'Movies',
      'Music',
      'Pictures',
    ]);
  });
}
