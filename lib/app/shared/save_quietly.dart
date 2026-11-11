import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_logger.dart';
import '../di/core_providers.dart';

/// Persists one setting after the in-memory state changed: a failed write is
/// logged, never thrown, and costs only the setting on the next launch.
Future<void> saveQuietly(Ref ref, String key, String value, String what) async {
  try {
    await ref.read(appStorageProvider).setString(key, value);
  } catch (e, s) {
    AppLogger.error('Could not save $what', e, s);
  }
}
