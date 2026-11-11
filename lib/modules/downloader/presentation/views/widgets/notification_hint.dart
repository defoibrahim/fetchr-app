import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../../app/shared/notification_permission_provider.dart';
import '../../../../../core/logging/app_logger.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/theme.dart';
import '../../../../../core/utils/scale.dart';
import '../../../../../core/widgets/app_button.dart';

const _padY = 10.0;
const _padLeft = 14.0;
const _padRight = 10.0;

/// Shown only while notifications are off: downloads still run, but their
/// progress stays inside the app. Allow asks, or opens the system settings
/// when Android will not show the dialog again.
class NotificationHint extends ConsumerStatefulWidget {
  const NotificationHint({super.key});

  @override
  ConsumerState<NotificationHint> createState() => _NotificationHintState();
}

class _NotificationHintState extends ConsumerState<NotificationHint>
    with WidgetsBindingObserver {
  bool _denied = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Back from the system settings, where the user may have turned them on.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    try {
      _setGranted(
        (await ref.read(notificationPermissionProvider).status()).isGranted,
      );
    } catch (e) {
      AppLogger.warning('Could not read the notification permission | $e');
    }
  }

  Future<void> _allow() async {
    final permission = ref.read(notificationPermissionProvider);
    try {
      final status = await permission.request();
      if (status.isPermanentlyDenied) await permission.openSettings();
      _setGranted(status.isGranted);
    } catch (e) {
      AppLogger.warning('Could not ask for the notification permission | $e');
    }
  }

  void _setGranted(bool granted) {
    if (!mounted || _denied == !granted) return;
    setState(() => _denied = !granted);
  }

  @override
  Widget build(BuildContext context) {
    if (!_denied) return const SizedBox.shrink();
    final tokens = context.tokens;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(Radii.row.r),
      ),
      child: Padding(
        padding: EdgeInsetsDirectional.only(
          start: _padLeft.w,
          end: _padRight.w,
          top: _padY.h,
          bottom: _padY.h,
        ),
        child: Row(
          spacing: Gap.md.w,
          children: [
            Expanded(
              child: Text(
                "Notifications are off. Downloads still run, but you won't see progress outside the app.",
                style: context.type.caption.copyWith(color: tokens.textMuted),
              ),
            ),
            AppButton(
              label: 'Allow',
              variant: AppButtonVariant.outlined,
              size: AppButtonSize.small,
              expanded: false,
              onPressed: _allow,
            ),
          ],
        ),
      ),
    );
  }
}
