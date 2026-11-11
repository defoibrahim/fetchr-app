import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:grabby/app/di/core_providers.dart';
import 'package:grabby/core/services/storage/app_storage.dart';

class MemoryStorage implements AppStorage {
  MemoryStorage([Map<String, String> initial = const {}])
    : values = {...initial};

  final Map<String, String> values;

  @override
  Future<String?> getString(String key) async => values[key];

  @override
  Future<void> setString(String key, String value) async => values[key] = value;

  @override
  Future<void> remove(String key) async => values.remove(key);
}

class ThrowingStorage extends MemoryStorage {
  @override
  Future<String?> getString(String key) => throw StateError('disk');

  @override
  Future<void> setString(String key, String value) => throw StateError('disk');
}

/// The caller disposes it: some tests dispose mid-test on purpose.
ProviderContainer containerWith(
  AppStorage storage, {
  List<Override> overrides = const [],
}) => ProviderContainer(
  overrides: [appStorageProvider.overrideWithValue(storage), ...overrides],
);
