import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/theme.dart';
import '../../../domain/entities/download_task.dart';
import '../../providers/downloads_notifier.dart';

/// The count on the Downloads tab: every task that is waiting, running,
/// paused or failed. Finished and cancelled ones need nothing from the user.
/// Draws nothing at zero; the shell places it.
class DownloadsBadge extends ConsumerWidget {
  const DownloadsBadge({super.key});

  // The nav bar's icons are raw design values, so the badge is too.
  static const _size = 16.0;
  static const _inset = 3.0;
  static const _maxShown = 9;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(
      downloadsNotifierProvider.select(
        (tasks) => tasks.value?.where(_needsAttention).length ?? 0,
      ),
    );
    if (count == 0) return const SizedBox.shrink();

    final tokens = context.tokens;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: _size, minHeight: _size),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: tokens.error,
          shape: const StadiumBorder(),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: _inset),
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: Text(
              count > _maxShown ? '$_maxShown+' : '$count',
              style: context.type.monoBadge.copyWith(
                color: tokens.onError,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }

  static bool _needsAttention(DownloadTask task) =>
      task.isActive || task.isPaused || task.status == TaskStatus.failed;
}
