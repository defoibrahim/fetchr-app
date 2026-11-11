import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/config/environment.dart';

void main() {
  test('the single environment is prod', () {
    expect(Environment.current, Environment.prod);
    expect(Environment.current.isProd, isTrue);
  });

  test('every base URL ends with a slash', () {
    for (final env in Environment.values) {
      expect(env.baseUrl.endsWith('/'), isTrue, reason: env.flavorName);
    }
  });
}
