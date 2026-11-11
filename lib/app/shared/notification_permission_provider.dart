import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/permissions/notification_permission.dart';

final notificationPermissionProvider = Provider<NotificationPermission>(
  (ref) => const NotificationPermission(),
);
