import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/app/bootstrap/bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the three font licences reach the licence page', () async {
    registerFontLicenses();

    final entries = await LicenseRegistry.licenses
        .where((e) => e.packages.any(_fonts.contains))
        .toList();

    expect(
      entries.expand((e) => e.packages).toSet().intersection(_fonts),
      _fonts,
    );
    for (final entry in entries) {
      final text = entry.paragraphs.map((p) => p.text).join('\n');
      expect(text, contains('SIL Open Font License'));
    }
  });
}

const _fonts = {'Bricolage Grotesque', 'Geist', 'JetBrains Mono'};
