import 'package:dio/dio.dart';

import '../logging/app_logger.dart';
import '../services/storage/token_store.dart';

class AppInterceptors extends Interceptor {
  AppInterceptors(this._tokenStore);

  final TokenStore _tokenStore;

  /// Set by the app layer; core can't reach the session to log out on a 401.
  static void Function()? onUnauthorized;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    options.headers['Accept'] = 'application/json';
    try {
      final token = await _tokenStore.read();
      // A pre-signed or third-party absolute URL must not receive the session token.
      if (token != null &&
          options.uri.host == Uri.parse(options.baseUrl).host) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    } catch (e, stack) {
      // An async throw here would never reach dio and the request would hang.
      AppLogger.error('Could not read the auth token', e, stack);
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.response?.statusCode == 401) onUnauthorized?.call();
    handler.next(err);
  }
}
