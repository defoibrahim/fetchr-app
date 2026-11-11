import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/errors/failure.dart';
import 'package:grabby/core/errors/result.dart';
import 'package:grabby/modules/settings/domain/usecases/set_yt_dlp_auto_update_usecase.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/mocks.dart';

void main() {
  late MockYtDlpRepository repository;
  late SetYtDlpAutoUpdateUseCase useCase;

  setUp(() {
    repository = MockYtDlpRepository();
    useCase = SetYtDlpAutoUpdateUseCase(repository);
  });

  for (final enabled in [true, false]) {
    test('forwards $enabled to the repository', () async {
      when(
        () => repository.setAutoUpdate(enabled),
      ).thenAnswer((_) async => const Ok<void>(null));

      final result = await useCase(enabled);

      expect(result.isOk, isTrue);
      verify(() => repository.setAutoUpdate(enabled)).called(1);
    });
  }

  test('passes a failure through unchanged', () async {
    when(
      () => repository.setAutoUpdate(any()),
    ).thenAnswer((_) async => const Err<void>(UnexpectedFailure()));

    final result = await useCase(true);

    expect(result.failureOrNull, const UnexpectedFailure());
  });
}
