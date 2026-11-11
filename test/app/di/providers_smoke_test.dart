import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/app/di/core_providers.dart';
import 'package:grabby/modules/downloader/di/downloader_providers.dart';
import 'package:grabby/modules/library/di/library_providers.dart';
import 'package:grabby/modules/settings/di/settings_providers.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

final _graph = <String, ProviderListenable<Object?>>{
  'secureStorageProvider': secureStorageProvider,
  'sharedPreferencesProvider': sharedPreferencesProvider,
  'internetConnectionProvider': internetConnectionProvider,
  'appStorageProvider': appStorageProvider,
  'tokenStoreProvider': tokenStoreProvider,
  'networkInfoProvider': networkInfoProvider,
  'dioProvider': dioProvider,
  'dioClientProvider': dioClientProvider,
  'fetchrHostApiProvider': fetchrHostApiProvider,
  'downloaderRepositoryProvider': downloaderRepositoryProvider,
  'fetchMediaInfoUseCaseProvider': fetchMediaInfoUseCaseProvider,
  'enqueueDownloadsUseCaseProvider': enqueueDownloadsUseCaseProvider,
  'cancelDownloadUseCaseProvider': cancelDownloadUseCaseProvider,
  'retryDownloadUseCaseProvider': retryDownloadUseCaseProvider,
  'pauseDownloadUseCaseProvider': pauseDownloadUseCaseProvider,
  'resumeDownloadUseCaseProvider': resumeDownloadUseCaseProvider,
  'pauseAllDownloadsUseCaseProvider': pauseAllDownloadsUseCaseProvider,
  'resumeAllDownloadsUseCaseProvider': resumeAllDownloadsUseCaseProvider,
  'getFreeSpaceUseCaseProvider': getFreeSpaceUseCaseProvider,
  'removeDownloadUseCaseProvider': removeDownloadUseCaseProvider,
  'openDownloadFolderUseCaseProvider': openDownloadFolderUseCaseProvider,
  'convertVideoUseCaseProvider': convertVideoUseCaseProvider,
  'watchDownloadsUseCaseProvider': watchDownloadsUseCaseProvider,
  'libraryRepositoryProvider': libraryRepositoryProvider,
  'getLibraryUseCaseProvider': getLibraryUseCaseProvider,
  'deleteLibraryItemsUseCaseProvider': deleteLibraryItemsUseCaseProvider,
  'shareLibraryItemUseCaseProvider': shareLibraryItemUseCaseProvider,
  'openLibraryFolderUseCaseProvider': openLibraryFolderUseCaseProvider,
  'getLibraryThumbnailUseCaseProvider': getLibraryThumbnailUseCaseProvider,
  'ytDlpRepositoryProvider': ytDlpRepositoryProvider,
  'getYtDlpStatusUseCaseProvider': getYtDlpStatusUseCaseProvider,
  'updateYtDlpUseCaseProvider': updateYtDlpUseCaseProvider,
  'setYtDlpAutoUpdateUseCaseProvider': setYtDlpAutoUpdateUseCaseProvider,
};

List<String> _declaredProviders() {
  final modules = Directory('lib/modules').listSync().whereType<Directory>();
  final folders = [
    Directory('lib/app/di'),
    for (final module in modules) Directory('${module.path}/di'),
  ];
  final declaration = RegExp(r'^final (\w+Provider)\b', multiLine: true);
  return [
    for (final folder in folders.where((d) => d.existsSync()))
      for (final file in folder.listSync().whereType<File>())
        if (file.path.endsWith('.dart'))
          for (final match in declaration.allMatches(file.readAsStringSync()))
            match.group(1)!,
  ]..sort();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('every provider builds', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final problems = <String>[];
    for (final MapEntry(:key, :value) in _graph.entries) {
      try {
        container.read(value);
      } catch (error) {
        final firstLine = error.toString().split('\n').first;
        problems.add('does not build: $key -> $firstLine');
      }
    }

    expect(problems, isEmpty);
  });

  test('every declared provider has a probe', () {
    expect(
      _graph.keys.toList()..sort(),
      _declaredProviders(),
      reason:
          'add one _graph entry per provider declared in lib/app/di '
          'or lib/modules/*/di',
    );
  });
}
