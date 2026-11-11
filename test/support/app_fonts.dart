import 'package:flutter/services.dart';

/// Loads the fonts the app ships under their pubspec families. Tests use the
/// Ahem-like test font otherwise, whose metrics round evenly and hide layout
/// that is off by a pixel with the real ones.
Future<void> loadAppFonts() async {
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final file in files) {
      loader.addFont(rootBundle.load(file));
    }
    await loader.load();
  }

  await family('Geist', [
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold'])
      'assets/fonts/Geist/Geist-$weight.ttf',
  ]);
  await family('Bricolage', [
    'assets/fonts/Bricolage/BricolageGrotesque-Bold.ttf',
  ]);
  await family('JetBrainsMono', [
    'assets/fonts/JetBrainsMono/JetBrainsMono-Regular.ttf',
    'assets/fonts/JetBrainsMono/JetBrainsMono-Medium.ttf',
  ]);
}
