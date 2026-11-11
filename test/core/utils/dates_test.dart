import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/utils/dates.dart';

void main() {
  group('dateFromMs', () {
    test('null stays null', () {
      expect(dateFromMs(null), isNull);
    });

    test('reads milliseconds since the epoch', () {
      expect(
        dateFromMs(1700000000000),
        DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
      expect(dateFromMs(0), DateTime.fromMillisecondsSinceEpoch(0));
    });
  });

  group('localDay', () {
    test('drops the time of day', () {
      expect(localDay(DateTime(2026, 10, 15, 23, 59)), DateTime(2026, 10, 15));
      expect(localDay(DateTime(2026, 10, 15)), DateTime(2026, 10, 15));
    });

    test('a UTC instant lands on its local day', () {
      final instant = DateTime.utc(2026, 10, 15, 12);
      final local = instant.toLocal();
      expect(localDay(instant), DateTime(local.year, local.month, local.day));
    });
  });
}
