import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';

abstract interface class INetworkInfo {
  Future<bool> get isConnected;
}

class NetworkInfoImpl implements INetworkInfo {
  NetworkInfoImpl(this._connection);

  final InternetConnection _connection;

  @override
  Future<bool> get isConnected => _connection.hasInternetAccess;
}
