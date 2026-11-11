import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/logging/log_filters.dart';

const _jwt =
    'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.'
    'SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c';

void main() {
  group('labelled secrets', () {
    const labels = [
      'token',
      'password',
      'secret',
      'authorization',
      'bearer',
      'pin',
      'otp',
      'ssn',
      'ss_no',
    ];

    test('masks the value after a colon or an equals sign', () {
      for (final label in labels) {
        expect(LogFilters.redact('$label: hunter2'), '$label: ***');
        expect(LogFilters.redact('$label=hunter2'), '$label: ***');
        expect(LogFilters.redact('$label = hunter2'), '$label: ***');
      }
    });

    test('is case insensitive and keeps the original label casing', () {
      expect(LogFilters.redact('Password: hunter2'), 'Password: ***');
      expect(LogFilters.redact('OTP=482913'), 'OTP: ***');
    });

    test('masks quoted JSON values', () {
      final out = LogFilters.redact('{"token":"abc123","id":7}');
      expect(out, isNot(contains('abc123')));
      expect(out, contains('"id":7'));
    });

    test('masks JSON nested in a JSON string', () {
      final out = LogFilters.redact(
        r'{"data":"{\"token\":\"abc123\",\"id\":7}"}',
      );
      expect(out, isNot(contains('abc123')));
      expect(out, contains(r'\"id\":7'));
    });

    test('stops at & so the rest of a query string survives', () {
      expect(
        LogFilters.redact('url ?token=abc123&driver=42&x=1'),
        'url ?token: ***&driver=42&x=1',
      );
    });

    test('masks snake and kebab case compound labels', () {
      expect(LogFilters.redact('access_token: abc123'), 'access_token: ***');
      expect(LogFilters.redact('fcm-token=abc123'), 'fcm-token: ***');
      expect(LogFilters.redact('user_ss_no: 123456789'), 'user_ss_no: ***');
    });

    test('camelCase and header labels', () {
      const cases = {
        'accessToken: abc': 'accessToken: ***',
        'apiKey=abc': 'apiKey: ***',
        'x-api-key: abc': 'x-api-key: ***',
        'clientSecret: abc': 'clientSecret: ***',
        'sessionId=abc': 'sessionId: ***',
        'credential: abc': 'credential: ***',
        'Cookie: session=abc; path=/': 'Cookie: ***; path=/',
        'Set-Cookie: a=b': 'Set-Cookie: ***',
        'Authorization: Basic dXNlcjpwYXNz': 'Authorization: ***',
      };
      cases.forEach((input, want) {
        expect(LogFilters.redact(input), want, reason: input);
      });
    });

    test('stops at a delimiter so neighbouring fields survive', () {
      expect(
        LogFilters.redact('token=abc123, driver=42; pin: 1234}'),
        'token: ***, driver=42; pin: ***}',
      );
    });

    test('masks the whole Authorization header, scheme included', () {
      expect(
        LogFilters.redact('Authorization: Bearer abc123xyz'),
        'Authorization: ***',
      );
    });
  });

  group('bearer without a colon', () {
    test('masks the token after the scheme', () {
      expect(
        LogFilters.redact('sent Bearer 12|AbC123xyz to server'),
        'sent Bearer *** to server',
      );
    });

    test('is case insensitive', () {
      expect(LogFilters.redact('bearer abc123xyz'), 'Bearer ***');
    });
  });

  group('JWT shaped strings', () {
    test('masks a bare JWT', () {
      expect(LogFilters.redact('session $_jwt ended'), 'session *** ended');
    });

    test('keeps the label when the JWT is a labelled value', () {
      expect(LogFilters.redact('token: $_jwt'), 'token: ***');
    });
  });

  group('coordinates', () {
    test('masks a lat,lng pair with or without a space', () {
      expect(
        LogFilters.redact('at 15.500700, 32.559900 now'),
        'at ***,*** now',
      );
      expect(LogFilters.redact('15.500700,32.559900'), '***,***');
    });

    test('masks negative coordinates', () {
      expect(LogFilters.redact('-33.868820, -151.209296'), '***,***');
    });

    test('masks labelled latitude and longitude values', () {
      expect(
        LogFilters.redact(
          '{latitude: 15.500700, longitude: 32.559900, heading: 90.0, speed: 0.0}',
        ),
        '{latitude: ***, longitude: ***, heading: 90.0, speed: 0.0}',
      );
      expect(
        LogFilters.redact('Latitude: 15.500700, Longitude: 32.559900'),
        'Latitude: ***, Longitude: ***',
      );
      expect(
        LogFilters.redact('{"lat":15.5,"lng":-32.5}'),
        '{"lat":***,"lng":***}',
      );
    });
  });

  group('dashed SSNs', () {
    test('a bare SSN-shaped number is left alone: that rule is not ported', () {
      expect(LogFilters.redact('on file 123-45-6789.'), 'on file 123-45-6789.');
    });

    test('a labelled SSN is still masked by the label rule', () {
      expect(LogFilters.redact('ssn: 123-45-6789'), 'ssn: ***');
    });
  });

  group('leaves ordinary text alone', () {
    const harmless = [
      'Retry 3 of 5',
      'took 1234 ms',
      'at 12:30:45',
      'at 12:30:45.123, then 13:00:00.456',
      'total 1,234.50 USD',
      'date 2026-10-05',
      'phone 555-1234',
      'v1.9.29+209',
      'package:grabby/core/utils/functions.dart:42:7',
      'com.defo.fetchr',
      'shipping: 5',
      'Token refreshed',
      'pin the map',
      'ratio 15.5, 32.5',
      'Exception: AuthController.updateUserProfile.something failed',
      'flat: 3',
    ];

    test('returns each input unchanged', () {
      for (final line in harmless) {
        expect(LogFilters.redact(line), line, reason: line);
      }
    });
  });

  group('order', () {
    test('a labelled bearer is not split by the bare Bearer rule', () {
      expect(LogFilters.redact('bearer = abc123xyz'), 'bearer: ***');
    });

    test('masks every kind in one line, and again is a no-op', () {
      final out = LogFilters.redact(
        'token: abc123 jwt $_jwt at 15.500700, 32.559900 '
        'sent Bearer xyz789',
      );
      expect(out, 'token: *** jwt *** at ***,*** sent Bearer ***');
      expect(LogFilters.redact(out), out);
    });
  });
}
