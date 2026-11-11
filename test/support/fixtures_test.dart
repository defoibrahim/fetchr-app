import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/errors/failure.dart';

import 'fixtures.dart';

void main() {
  group('downloadTask', () {
    test('asks for a request of its own per id', () {
      final a = downloadTask(id: 'a');

      expect(a.request.url, 'https://example.com/a');
      expect(a.request.title, 'Video a');
      expect(a, isNot(downloadTask(id: 'b')));
    });

    test('an error code maps to its failure and an explicit one wins', () {
      expect(
        downloadTask(errorCode: 'private_video').failure,
        const PrivateVideoFailure(),
      );
      expect(
        downloadTask(errorCode: 'permission_denied').failure,
        const StoragePermissionFailure(),
      );
      expect(
        downloadTask(
          errorCode: 'private_video',
          failure: const NetworkFailure(),
        ).failure,
        const NetworkFailure(),
      );
      expect(downloadTask().failure, isNull);
    });
  });
}
