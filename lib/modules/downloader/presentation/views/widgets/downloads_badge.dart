import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/theme.dart';
import '../../../../../core/widgets/app_fade_switcher.dart';
import '../../../domain/entities/download_task.dart';
import '../../providers/downloads_notifier.dart';

/// The count on the Downloads tab: every task that is waiting, running,
/// paused or failed. Finished and cancelled ones need nothing from the user.
/// Draws nothing at zero; the shell places it.
///
/// It pops in when the first task arrives, bumps when the count goes up,
/// cross-fades its number, and shrinks away at zero.
class DownloadsBadge extends ConsumerWidget {
  const DownloadsBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(
      downloadsNotifierProvider.select(
        (tasks) => tasks.value?.where(_needsAttention).length ?? 0,
      ),
    );
    return CountBadge(count: count);
  }

  static bool _needsAttention(DownloadTask task) =>
      task.isActive || task.isPaused || task.status == TaskStatus.failed;
}

/// The badge itself, for a count from anywhere.
class CountBadge extends StatefulWidget {
  const CountBadge({super.key, required this.count});

  /// The bump on an increase: up to 1.2 and back, over 220 ms.
  static const bump = Duration(milliseconds: 220);

  final int count;

  @override
  State<CountBadge> createState() => _CountBadgeState();
}

class _CountBadgeState extends State<CountBadge> with TickerProviderStateMixin {
  // The nav bar's icons are raw design values, so the badge is too.
  static const _size = 16.0;
  static const _inset = 3.0;
  static const _maxShown = 9;

  static const _presenceSpec = MotionSpec(
    Motion.medium,
    Motion.standard,
    reverseDuration: Motion.fast,
  );

  /// 0 is gone, 1 is shown: in over 250 ms with an overshoot, out over 150.
  late final _presence = AnimationController(
    vsync: this,
    value: widget.count > 0 ? 1 : 0,
  )..addStatusListener(_onPresence);
  late final _shown = CurvedAnimation(
    parent: _presence,
    curve: Motion.pop,
    reverseCurve: Motion.exit,
  );
  late final _bump = AnimationController(
    vsync: this,
    duration: CountBadge.bump,
  );
  // Up for the first 40% of the bump, back down for the rest.
  late final Animation<double> _bumpScale = TweenSequence([
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 1,
        end: 1.2,
      ).chain(CurveTween(curve: Motion.standard)),
      weight: 40,
    ),
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 1.2,
        end: 1,
      ).chain(CurveTween(curve: Motion.standard)),
      weight: 60,
    ),
  ]).animate(_bump);

  /// The last count above zero, kept while the badge shrinks away.
  late int _label = widget.count;

  @override
  void didUpdateWidget(CountBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    final from = oldWidget.count;
    final to = widget.count;
    if (to == from) return;
    if (to > 0) _label = to;
    final reduce = context.reduceMotion;
    final presence = context.motionOf(_presenceSpec);
    _presence
      ..duration = presence.duration
      ..reverseDuration = presence.reverseDuration;
    if (to == 0) {
      _presence.reverse();
    } else if (from == 0 || !_presence.isForwardOrCompleted) {
      _presence.forward();
    } else if (to > from && !reduce) {
      _bump.forward(from: 0);
    }
  }

  void _onPresence(AnimationStatus status) {
    if (status.isDismissed && mounted) setState(() {});
  }

  @override
  void dispose() {
    _shown.dispose();
    _presence.dispose();
    _bump.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_presence.isDismissed && widget.count == 0) {
      return const SizedBox.shrink();
    }
    final tokens = context.tokens;
    final label = _label > _maxShown ? '$_maxShown+' : '$_label';
    return ScaleTransition(
      scale: _shown,
      child: FadeTransition(
        opacity: _presence,
        child: ScaleTransition(
          scale: _bumpScale,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: _size,
              minHeight: _size,
            ),
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
                  child: AppFadeSwitcher(
                    spec: Motion.fade,
                    scaleFrom: 1,
                    alignment: Alignment.center,
                    child: Text(
                      label,
                      key: ValueKey(label),
                      style: context.type.monoBadge.copyWith(
                        color: tokens.onError,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
