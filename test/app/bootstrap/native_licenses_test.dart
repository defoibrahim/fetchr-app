import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/app/bootstrap/bootstrap.dart';
import 'package:grabby/core/platform/platform_traits.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(LicenseRegistry.reset);
  tearDown(LicenseRegistry.reset);

  Future<List<LicenseEntry>> all() => LicenseRegistry.licenses.toList();

  String textOf(LicenseEntry entry) =>
      entry.paragraphs.map((p) => p.text).join('\n');

  test('iOS lists what its native layer bundles', () async {
    registerNativeLicenses(PlatformTraits.ios);

    final entries = await all();
    final names = entries.expand((e) => e.packages).toList();

    expect(names, contains(startsWith('CPython ')));
    expect(names, contains('FFmpeg, FFmpegKit and LAME (libmp3lame)'));
    expect(names, contains(startsWith('yt-dlp ')));
    expect(names, contains(startsWith('yt-dlp-ejs ')));
    expect(names, contains(startsWith('mutagen ')));
    final ffmpeg = entries.firstWhere(
      (e) => e.packages.contains('FFmpeg, FFmpegKit and LAME (libmp3lame)'),
    );
    expect(textOf(ffmpeg), contains('GNU LESSER GENERAL PUBLIC LICENSE'));
    expect(textOf(ffmpeg), contains('GNU GENERAL PUBLIC LICENSE'));
    final ejs = entries.firstWhere(
      (e) => e.packages.any((p) => p.startsWith('yt-dlp-ejs ')),
    );
    expect(textOf(ejs), contains('meriyah'));
  });

  test('Android adds none: its native layer is not this bundle', () async {
    registerNativeLicenses(PlatformTraits.android);

    expect(await all(), isEmpty);
  });
}
