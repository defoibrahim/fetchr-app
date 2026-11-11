import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/app/shared/domain/entities/yt_dlp_status.dart';
import 'package:grabby/app/shared/yt_dlp_provider.dart';
import 'package:grabby/core/errors/failure.dart';
import 'package:grabby/core/errors/result.dart';
import 'package:grabby/modules/settings/di/settings_providers.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/mocks.dart';

void main() {
  const loaded = YtDlpStatus(version: '2026.10.01', autoUpdate: true);
  const updated = YtDlpStatus(version: '2026.10.14', autoUpdate: true);

  late MockYtDlpRepository repository;
  late ProviderContainer container;

  AsyncValue<YtDlpState> state() => container.read(ytDlpProvider);

  YtDlpNotifier notifier() => container.read(ytDlpProvider.notifier);

  void open(Result<YtDlpStatus> status) {
    when(() => repository.status()).thenAnswer((_) async => status);
    container = ProviderContainer(
      overrides: [ytDlpRepositoryProvider.overrideWithValue(repository)],
    );
  }

  Future<void> settle() =>
      container.read(ytDlpProvider.future).then<void>((_) {}, onError: (_) {});

  setUp(() => repository = MockYtDlpRepository());

  tearDown(() => container.dispose());

  group('build', () {
    test('starts loading, then holds the status with phase idle', () async {
      open(const Ok(loaded));

      expect(state().isLoading, isTrue);
      expect(
        await container.read(ytDlpProvider.future),
        const YtDlpState(loaded),
      );
      expect(state().requireValue.phase, YtDlpUpdatePhase.idle);
    });

    test('a bundled copy holds a null version', () async {
      open(const Ok(YtDlpStatus(autoUpdate: true)));
      await settle();

      expect(state().requireValue.status?.version, isNull);
    });

    test('a failure is in the error state, not retried', () async {
      open(const Err<YtDlpStatus>(UnexpectedFailure()));
      await settle();

      expect(state().hasError, isTrue);
      expect(state().error, const UnexpectedFailure());
      verify(() => repository.status()).called(1);
    });

    test('is not disposed once nothing listens to it', () async {
      open(const Ok(loaded));
      await settle();

      await Future<void>.delayed(Duration.zero);

      expect(state().hasValue, isTrue);
      verify(() => repository.status()).called(1);
    });
  });

  group('updateYtDlp', () {
    test('goes busy, then done with the new status', () async {
      open(const Ok(loaded));
      await settle();
      final gate = Completer<Result<YtDlpStatus>>();
      when(() => repository.update()).thenAnswer((_) => gate.future);

      final pending = notifier().updateYtDlp();
      await pumpEventQueue();

      expect(
        state().requireValue,
        const YtDlpState(loaded, phase: YtDlpUpdatePhase.busy),
      );

      gate.complete(const Ok(updated));
      final result = await pending;

      expect(result, const Ok(updated));
      expect(
        state().requireValue,
        const YtDlpState(updated, phase: YtDlpUpdatePhase.done),
      );
    });

    test('a failure keeps the status and returns to idle', () async {
      open(const Ok(loaded));
      await settle();
      when(
        () => repository.update(),
      ).thenAnswer((_) async => const Err<YtDlpStatus>(YtDlpBusyFailure()));

      final result = await notifier().updateYtDlp();

      expect(result.failureOrNull, const YtDlpBusyFailure());
      expect(state().requireValue, const YtDlpState(loaded));
    });

    test('a failure after done returns to idle too', () async {
      open(const Ok(loaded));
      await settle();
      when(
        () => repository.update(),
      ).thenAnswer((_) async => const Ok(updated));
      await notifier().updateYtDlp();
      when(
        () => repository.update(),
      ).thenAnswer((_) async => const Err<YtDlpStatus>(NetworkFailure()));

      await notifier().updateYtDlp();

      expect(state().requireValue, const YtDlpState(updated));
    });

    test('a second call while busy returns the same future', () async {
      open(const Ok(loaded));
      await settle();
      final gate = Completer<Result<YtDlpStatus>>();
      when(() => repository.update()).thenAnswer((_) => gate.future);

      final first = notifier().updateYtDlp();
      final second = notifier().updateYtDlp();

      expect(identical(first, second), isTrue);
      gate.complete(const Ok(updated));
      await first;
      verify(() => repository.update()).called(1);
    });

    test('can run again once the first update has finished', () async {
      open(const Ok(loaded));
      await settle();
      when(
        () => repository.update(),
      ).thenAnswer((_) async => const Ok(updated));

      await notifier().updateYtDlp();
      await notifier().updateYtDlp();

      verify(() => repository.update()).called(2);
    });

    test('after a failed read an update shows busy, then the status', () async {
      open(const Err<YtDlpStatus>(UnexpectedFailure()));
      await settle();
      final gate = Completer<Result<YtDlpStatus>>();
      when(() => repository.update()).thenAnswer((_) => gate.future);

      final pending = notifier().updateYtDlp();
      await pumpEventQueue();
      expect(
        state().requireValue,
        const YtDlpState(null, phase: YtDlpUpdatePhase.busy),
      );

      gate.complete(const Ok(updated));
      await pending;

      expect(
        state().requireValue,
        const YtDlpState(updated, phase: YtDlpUpdatePhase.done),
      );
    });

    test(
      'after a failed read a failed update reads the status again',
      () async {
        open(const Err<YtDlpStatus>(UnexpectedFailure()));
        await settle();
        when(
          () => repository.update(),
        ).thenAnswer((_) async => const Err<YtDlpStatus>(NetworkFailure()));
        when(
          () => repository.status(),
        ).thenAnswer((_) async => const Ok(loaded));

        await notifier().updateYtDlp();
        await settle();

        expect(state().requireValue, const YtDlpState(loaded));
      },
    );

    test('a result landing after disposal still returns', () async {
      open(const Ok(loaded));
      await settle();
      final gate = Completer<Result<YtDlpStatus>>();
      when(() => repository.update()).thenAnswer((_) => gate.future);

      final pending = notifier().updateYtDlp();
      container.dispose();
      gate.complete(const Ok(updated));

      expect(await pending, const Ok(updated));
    });
  });

  group('setAutoUpdate', () {
    test('flips the state at once and keeps it on Ok', () async {
      open(const Ok(loaded));
      await settle();
      final gate = Completer<Result<void>>();
      when(
        () => repository.setAutoUpdate(false),
      ).thenAnswer((_) => gate.future);

      final pending = notifier().setAutoUpdate(false);

      expect(state().requireValue.status?.autoUpdate, isFalse);
      gate.complete(const Ok<void>(null));
      expect((await pending).isOk, isTrue);
      expect(state().requireValue.status?.autoUpdate, isFalse);
    });

    test('restores the previous value on Err', () async {
      open(const Ok(loaded));
      await settle();
      when(
        () => repository.setAutoUpdate(false),
      ).thenAnswer((_) async => const Err<void>(UnexpectedFailure()));

      final result = await notifier().setAutoUpdate(false);

      expect(result.failureOrNull, const UnexpectedFailure());
      expect(state().requireValue.status?.autoUpdate, isTrue);
    });

    test('keeps the version and phase it flips beside', () async {
      open(const Ok(loaded));
      await settle();
      when(
        () => repository.setAutoUpdate(false),
      ).thenAnswer((_) async => const Ok<void>(null));

      await notifier().setAutoUpdate(false);

      expect(
        state().requireValue,
        const YtDlpState(YtDlpStatus(version: '2026.10.01', autoUpdate: false)),
      );
    });

    test(
      'with no status loaded it still calls native, state untouched',
      () async {
        open(const Err<YtDlpStatus>(UnexpectedFailure()));
        await settle();
        when(
          () => repository.setAutoUpdate(true),
        ).thenAnswer((_) async => const Ok<void>(null));

        final result = await notifier().setAutoUpdate(true);

        expect(result.isOk, isTrue);
        expect(state().hasError, isTrue);
      },
    );
  });
}
