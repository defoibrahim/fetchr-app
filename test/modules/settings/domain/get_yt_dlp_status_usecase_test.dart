import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/app/shared/domain/entities/yt_dlp_status.dart';
import 'package:grabby/core/errors/failure.dart';
import 'package:grabby/core/errors/result.dart';
import 'package:grabby/core/usecase/base_use_case.dart';
import 'package:grabby/modules/settings/domain/usecases/get_yt_dlp_status_usecase.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/mocks.dart';

void main() {
  const status = YtDlpStatus(version: '2026.10.01', autoUpdate: true);

  late MockYtDlpRepository repository;
  late GetYtDlpStatusUseCase useCase;

  setUp(() {
    repository = MockYtDlpRepository();
    useCase = GetYtDlpStatusUseCase(repository);
  });

  test('returns the repository status', () async {
    when(() => repository.status()).thenAnswer((_) async => const Ok(status));

    final result = await useCase(const NoParams());

    expect(result, const Ok(status));
    verify(() => repository.status()).called(1);
  });

  test('passes a failure through unchanged', () async {
    when(
      () => repository.status(),
    ).thenAnswer((_) async => const Err<YtDlpStatus>(UnexpectedFailure()));

    final result = await useCase(const NoParams());

    expect(result.failureOrNull, const UnexpectedFailure());
  });
}
