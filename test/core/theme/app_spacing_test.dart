import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/theme/app_spacing.dart';

void main() {
  group('WindowClass.of', () {
    for (final (width, expected) in [
      (359.0, WindowClass.narrow),
      (360.0, WindowClass.compact),
      (599.0, WindowClass.compact),
      (600.0, WindowClass.medium),
      (839.0, WindowClass.medium),
      (840.0, WindowClass.expanded),
    ]) {
      test('$width dp is $expected', () {
        expect(WindowClass.of(width), expected);
      });
    }
  });

  test('isAtLeast orders narrow, compact, medium and expanded', () {
    expect(WindowClass.expanded.isAtLeast(WindowClass.medium), isTrue);
    expect(WindowClass.medium.isAtLeast(WindowClass.medium), isTrue);
    expect(WindowClass.compact.isAtLeast(WindowClass.medium), isFalse);
    expect(WindowClass.narrow.isAtLeast(WindowClass.compact), isFalse);
  });

  test('the breakpoints and caps are the spec values', () {
    expect(Breakpoints.narrow, 360);
    expect(Breakpoints.medium, 600);
    expect(Breakpoints.expanded, 840);
    expect(Breakpoints.compactHeight, 480);
    expect(Breakpoints.contentMax, 560);
    expect(Breakpoints.dialogWidth, 480);
  });
}
