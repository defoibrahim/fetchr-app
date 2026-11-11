import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../errors/failure.dart';
import '../errors/failure_mapper.dart';
import '../errors/result.dart';
import '../logging/app_logger.dart';
import '../services/storage/token_store.dart';
import 'api_constants.dart';
import 'http_method.dart';
import 'interceptors.dart';

typedef ResponseConverter<T> = T Function(Object? data);

Dio buildDio({required String baseUrl, required TokenStore tokenStore}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      contentType: Headers.jsonContentType,
      connectTimeout: ApiConstants.connectTimeout,
      receiveTimeout: ApiConstants.receiveTimeout,
      sendTimeout: ApiConstants.sendTimeout,
    ),
  );
  dio.interceptors.add(AppInterceptors(tokenStore));
  if (kDebugMode) dio.interceptors.add(_RequestLogger());
  return dio;
}

class DioClient {
  DioClient(this._dio);

  final Dio _dio;

  Future<Result<T>> makeRequest<T>({
    required String path,
    HttpMethod method = HttpMethod.get,
    Object? data,
    Map<String, dynamic>? queryParams,
    required ResponseConverter<T> converter,
    bool isIsolate = false,
  }) async {
    try {
      final response = await _dio.request<Object?>(
        path,
        data: data,
        queryParameters: queryParams,
        options: Options(method: method.name.toUpperCase()),
      );
      // A 204 (or any empty body) reaches the converter as null, not ''.
      final raw = response.data;
      final body = raw == '' ? null : raw;
      final value = isIsolate
          ? await compute<Object?, T>(converter, body)
          : converter(body);
      return Ok(value);
    } on DioException catch (e) {
      return Err(failureFrom(e));
    } catch (e, stack) {
      AppLogger.error('Could not convert the response of $path', e, stack);
      return Err<T>(const UnexpectedFailure());
    }
  }
}

// Logs method, path (never the query), status and duration; nothing else.
class _RequestLogger extends Interceptor {
  static const _startKey = 'request_stopwatch';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_startKey] = Stopwatch()..start();
    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler h) {
    _log(response.requestOptions, response.statusCode);
    h.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _log(err.requestOptions, err.response?.statusCode, err.type.name);
    handler.next(err);
  }

  void _log(RequestOptions options, int? status, [String? failure]) {
    final watch = options.extra[_startKey];
    final ms = watch is Stopwatch ? watch.elapsedMilliseconds : -1;
    AppLogger.debug(
      '${options.method} ${options.path} -> ${status ?? failure} (${ms}ms)',
    );
  }
}
