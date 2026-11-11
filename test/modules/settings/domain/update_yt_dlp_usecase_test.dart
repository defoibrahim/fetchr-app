import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/app/shared/domain/entities/yt_dlp_status.dart';
import 'package:grabby/core/errors/failure.dart';
import 'package:grabby/core/errors/result.dart';
import 'package:grabby/core/usecase/base_use_case.dart';
import 'package:grabby/modules/settings/domain/usecases/update_yt_dlp_usecase.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/mocks.dart';

void main() {
  late MockYtDlpRepository repository;
  late UpdateYtDlpUseCase useCase;

  setUp(() {
    repository = MockYtDlpRepository();
    useCase = UpdateYtDlpUseCase(repository);
  });

  test('returns the new status', () async {
    const status = YtDlpStatus(version: '2026.10.14', autoUpdate: true);
    when(() => repository.update()).thenAnswer((_) async => const Ok(status));

    final result = await useCase(const NoParams());

    expect(result, const Ok(status));
    verify(() => repository.update()).called(1);
  });

  test('passes a failure through unchanged', () async {
    when(
      () => repository.update(),
    ).thenAnswer((_) async => const Err<YtDlpStatus>(YtDlpBusyFailure()));

    final result = await useCase(const NoParams());

    expect(result.failureOrNull, const YtDlpBusyFailure());
  });
}
