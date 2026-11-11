import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/app/shared/domain/entities/yt_dlp_status.dart';
import 'package:grabby/core/errors/error_messages.dart';
import 'package:grabby/core/errors/failure.dart';
import 'package:grabby/core/errors/result.dart';
import 'package:grabby/core/platform/fetchr_api.g.dart' as native;
import 'package:grabby/modules/settings/data/repositories/yt_dlp_repository_impl.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/mocks.dart';

void main() {
  late MockFetchrHostApi api;
  late MockNetworkInfo network;
  late YtDlpRepositoryImpl repository;

  const offline = NetworkFailure(ErrorMessages.ytDlpUpdateOffline);

  setUp(() {
    api = MockFetchrHostApi();
    network = MockNetworkInfo();
    repository = YtDlpRepositoryImpl(api, network);
  });

  group('status', () {
    test('maps every field without a connectivity check', () async {
      when(() => api.ytDlpStatus()).thenAnswer(
        (_) async => native.YtDlpStatus(
          version: '2026.10.01',
          checkedAtMs: 1700000000000,
          autoUpdate: false,
        ),
      );

      final result = await repository.status();

      expect(
        result.valueOrNull,
        YtDlpStatus(
          version: '2026.10.01',
          checkedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
          autoUpdate: false,
        ),
      );
      verifyNever(() => network.isConnected);
    });

    test('keeps a missing version and check time null', () async {
      when(
        () => api.ytDlpStatus(),
      ).thenAnswer((_) async => native.YtDlpStatus(autoUpdate: true));

      final result = await repository.status();

      expect(result.isOk, isTrue);
      expect(result.valueOrNull, const YtDlpStatus(autoUpdate: true));
    });

    test('maps a platform error to a failure', () async {
      when(
        () => api.ytDlpStatus(),
      ).thenThrow(PlatformException(code: 'unknown'));

      final result = await repository.status();

      expect(result.failureOrNull, isA<UnexpectedFailure>());
    });
  });

  group('update', () {
    test('offline returns the update offline text without native', () async {
      when(() => network.isConnected).thenAnswer((_) async => false);

      final result = await repository.update();

      expect(result.failureOrNull, offline);
      verifyNever(() => api.updateYtDlp());
    });

    test('online returns the new status', () async {
      when(() => network.isConnected).thenAnswer((_) async => true);
      when(() => api.updateYtDlp()).thenAnswer(
        (_) async => native.YtDlpStatus(
          version: '2026.10.14',
          checkedAtMs: 1700000100000,
          autoUpdate: true,
        ),
      );

      final result = await repository.update();

      expect(
        result.valueOrNull,
        YtDlpStatus(
          version: '2026.10.14',
          checkedAt: DateTime.fromMillisecondsSinceEpoch(1700000100000),
          autoUpdate: true,
        ),
      );
      verify(() => api.updateYtDlp()).called(1);
    });

    test('maps busy to YtDlpBusyFailure', () async {
      when(() => network.isConnected).thenAnswer((_) async => true);
      when(
        () => api.updateYtDlp(),
      ).thenThrow(PlatformException(code: 'busy', message: 'running'));

      final result = await repository.update();

      expect(result.failureOrNull, const YtDlpBusyFailure());
    });

    test('a native network error gets the update offline text too', () async {
      when(() => network.isConnected).thenAnswer((_) async => true);
      when(
        () => api.updateYtDlp(),
      ).thenThrow(PlatformException(code: 'network'));

      final result = await repository.update();

      expect(result.failureOrNull, offline);
    });
  });

  group('setAutoUpdate', () {
    test('passes the flag to native without a connectivity check', () async {
      when(() => api.setYtDlpAutoUpdate(any())).thenAnswer((_) async {});

      final result = await repository.setAutoUpdate(false);

      expect(result.isOk, isTrue);
      verify(() => api.setYtDlpAutoUpdate(false)).called(1);
      verifyNever(() => network.isConnected);
    });

    test('maps a platform error to a failure', () async {
      when(
        () => api.setYtDlpAutoUpdate(any()),
      ).thenThrow(PlatformException(code: 'unknown'));

      final result = await repository.setAutoUpdate(true);

      expect(result.failureOrNull, isA<UnexpectedFailure>());
    });
  });
}
