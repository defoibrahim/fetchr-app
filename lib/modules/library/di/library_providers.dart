import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/core_providers.dart';
import '../data/repositories/library_repository_impl.dart';
import '../domain/repositories/i_library_repository.dart';
import '../domain/usecases/delete_library_items_usecase.dart';
import '../domain/usecases/get_library_thumbnail_usecase.dart';
import '../domain/usecases/get_library_usecase.dart';
import '../domain/usecases/open_library_folder_usecase.dart';
import '../domain/usecases/share_library_item_usecase.dart';

final libraryRepositoryProvider = Provider<ILibraryRepository>(
  (ref) => LibraryRepositoryImpl(ref.watch(fetchrHostApiProvider)),
);

final getLibraryUseCaseProvider = Provider<GetLibraryUseCase>(
  (ref) => GetLibraryUseCase(ref.watch(libraryRepositoryProvider)),
);

final getLibraryThumbnailUseCaseProvider = Provider<GetLibraryThumbnailUseCase>(
  (ref) => GetLibraryThumbnailUseCase(ref.watch(libraryRepositoryProvider)),
);

final deleteLibraryItemsUseCaseProvider = Provider<DeleteLibraryItemsUseCase>(
  (ref) => DeleteLibraryItemsUseCase(ref.watch(libraryRepositoryProvider)),
);

final shareLibraryItemUseCaseProvider = Provider<ShareLibraryItemUseCase>(
  (ref) => ShareLibraryItemUseCase(ref.watch(libraryRepositoryProvider)),
);

final openLibraryFolderUseCaseProvider = Provider<OpenLibraryFolderUseCase>(
  (ref) => OpenLibraryFolderUseCase(ref.watch(libraryRepositoryProvider)),
);
