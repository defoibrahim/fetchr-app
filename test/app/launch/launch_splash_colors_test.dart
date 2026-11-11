import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/app/launch/launch_intro.dart';
import 'package:grabby/core/theme/theme.dart';

const _res = 'android/app/src/main/res';

/// The `<color>` entries of an Android colors.xml, by name. Tests run from the
/// repo root.
Map<String, Color> _colors(String folder) {
  final xml = File('$_res/$folder/colors.xml').readAsStringSync();
  return {
    for (final m in RegExp(
      r'<color name="(\w+)">#([0-9A-Fa-f]{8})</color>',
    ).allMatches(xml))
      m[1]!: Color(int.parse(m[2]!, radix: 16)),
  };
}

void main() {
  group('the Dart splash colours match the native splash', () {
    for (final (folder, brightness) in [
      ('values', Brightness.light),
      ('values-night', Brightness.dark),
    ]) {
      test('${brightness.name}: $folder/colors.xml', () {
        final native = _colors(folder);
        final dart = launchSplashColors(brightness);

        expect(native['splash_background'], dart.background);
        expect(native['splash_tile'], dart.tile);
        expect(native['splash_glyph'], dart.glyph);
      });
    }

    test('the launcher icon is the lime tile with the ink glyph', () {
      final native = _colors('values');
      expect(native['ic_launcher_background'], AppPalette.defaultAccent);
      expect(native['ic_launcher_glyph'], AppPalette.dark.onAccent);
    });
  });
}
