import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/modules/downloader/domain/extensions/string_extensions.dart';

void main() {
  group('firstUrl', () {
    const cases = <String?, String?>{
      null: null,
      '': null,
      '   ': null,
      'no link here': null,
      'https://youtu.be/abc': 'https://youtu.be/abc',
      '  https://youtu.be/abc\n': 'https://youtu.be/abc',
      'Watch this https://youtu.be/abc now': 'https://youtu.be/abc',
      'Cool video\nhttps://youtu.be/abc\nsent from app': 'https://youtu.be/abc',
      'http://example.com/a?b=c&d=e#f': 'http://example.com/a?b=c&d=e#f',
      'HTTPS://Example.com/Path': 'HTTPS://Example.com/Path',
      'http://localhost:8080/x': 'http://localhost:8080/x',
      'see https://example.com/x.': 'https://example.com/x',
      'see https://example.com/x, then': 'https://example.com/x',
      'really? https://example.com/x!': 'https://example.com/x',
      '(https://example.com/x)': 'https://example.com/x',
      '[a](https://example.com/x)': 'https://example.com/x',
      '"https://example.com/x",': 'https://example.com/x',
      '<https://example.com/x>': 'https://example.com/x',
      'https://en.wikipedia.org/wiki/Foo_(bar)':
          'https://en.wikipedia.org/wiki/Foo_(bar)',
      '(https://en.wikipedia.org/wiki/Foo_(bar))':
          'https://en.wikipedia.org/wiki/Foo_(bar)',
      'ftp://example.com/x': null,
      'mailto:a@b.com': null,
      'example.com/x': null,
      'xhttps://example.com': null,
      'https://': null,
      'https:// example.com': null,
      'https:///path': null,
      'https://?x=1': null,
      'https://?x http://b.com/y': 'http://b.com/y',
      'https://a.com/1 https://b.com/2': 'https://a.com/1',
    };

    cases.forEach((input, expected) {
      test('$input -> $expected', () {
        expect(input.firstUrl, expected);
      });
    });
  });
}
