import '../config/environment.dart';

abstract final class ApiConstants {
  static String get baseUrl => Environment.current.baseUrl;

  static const connectTimeout = Duration(seconds: 20);
  static const receiveTimeout = Duration(seconds: 30);
  static const sendTimeout = Duration(seconds: 30);
}
