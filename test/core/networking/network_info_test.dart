import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/networking/network_info.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:mocktail/mocktail.dart';

class _MockInternetConnection extends Mock implements InternetConnection {}

void main() {
  late _MockInternetConnection connection;
  late NetworkInfoImpl info;

  setUp(() {
    connection = _MockInternetConnection();
    info = NetworkInfoImpl(connection);
  });

  test('isConnected is true when the connection has internet access', () async {
    when(() => connection.hasInternetAccess).thenAnswer((_) async => true);

    expect(await info.isConnected, isTrue);
  });

  test('isConnected is false when it has none', () async {
    when(() => connection.hasInternetAccess).thenAnswer((_) async => false);

    expect(await info.isConnected, isFalse);
  });
}
