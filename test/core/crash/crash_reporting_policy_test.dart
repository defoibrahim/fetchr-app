import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/crash/crash_reporting_policy.dart';

void main() {
  group('reportsCrashes', () {
    test('reports from a real device', () {
      expect(reportsCrashes(const {'HOME': '/var/mobile'}), isTrue);
    });

    test('stays silent on the iOS simulator', () {
      expect(
        reportsCrashes(const {'SIMULATOR_DEVICE_NAME': 'iPhone 17'}),
        isFalse,
      );
    });

    test('stays silent inside an XCTest run', () {
      expect(
        reportsCrashes(const {
          'XCTestConfigurationFilePath': '/tmp/x.xctestconfiguration',
        }),
        isFalse,
      );
    });
  });
}
