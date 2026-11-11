import 'dart:typed_data';

import 'package:dio/dio.dart';

typedef FakeResponder = Future<ResponseBody> Function(RequestOptions options);

class FakeHttpAdapter implements HttpClientAdapter {
  FakeHttpAdapter(this._respond);

  /// A JSON body with the given status; `body` is sent as is.
  factory FakeHttpAdapter.json(String body, {int status = 200}) =>
      FakeHttpAdapter((_) async => jsonResponse(body, status: status));

  /// An empty body, as sent with a 204.
  factory FakeHttpAdapter.empty({int status = 204}) =>
      FakeHttpAdapter((_) async => ResponseBody.fromString('', status));

  /// Fails every request with an exception built from the request.
  factory FakeHttpAdapter.failing(Object Function(RequestOptions) error) =>
      FakeHttpAdapter((options) => throw error(options));

  final FakeResponder _respond;
  final List<RequestOptions> requests = [];

  RequestOptions get lastRequest => requests.last;

  static ResponseBody jsonResponse(String body, {int status = 200}) =>
      ResponseBody.fromString(
        body,
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requests.add(options);
    return _respond(options);
  }

  @override
  void close({bool force = false}) {}
}
