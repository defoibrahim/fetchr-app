import 'package:flutter/material.dart';

import '../../core/theme/theme.dart';
import '../../core/widgets/inert.dart';

/// The tabs' navigators, one on screen at a time like go_router's indexed
/// stack, with a fade-through on a switch: the old tab fades out over the
/// first 90 ms, then the new one fades in from 98% scale. Instant under reduce
/// motion, and never on the first build.
///
/// Like the indexed stack, only the current tab has tickers (a tab that is
/// shown again sees `TickerMode` turn on, which Library reloads on), heroes,
/// focus and taps; a tab that is fully hidden is offstage. Every tab keeps the
/// same widgets whatever its state, so no tab's state is lost to a switch.
class AppBranchSwitcher extends StatefulWidget {
  const AppBranchSwitcher({
    super.key,
    required this.currentIndex,
    required this.children,
  });

  static const duration = Motion.medium;
  static const fadeOut = Duration(milliseconds: 90);
  static const scaleFrom = .98;

  final int currentIndex;
  final List<Widget> children;

  @override
  State<AppBranchSwitcher> createState() => _AppBranchSwitcherState();
}

class _AppBranchSwitcherState extends State<AppBranchSwitcher>
    with SingleTickerProviderStateMixin {
  static final _split =
      AppBranchSwitcher.fadeOut.inMicroseconds /
      AppBranchSwitcher.duration.inMicroseconds;
  static const _shown = AlwaysStoppedAnimation(1.0);
  static const _hidden = AlwaysStoppedAnimation(0.0);

  late final _controller = AnimationController(
    vsync: this,
    duration: AppBranchSwitcher.duration,
    value: 1,
  )..addStatusListener(_onStatus);
  late final Animation<double> _in = _controller.drive(
    CurveTween(curve: Interval(_split, 1, curve: Motion.enter)),
  );
  late final Animation<double> _scale = _in.drive(
    Tween(begin: AppBranchSwitcher.scaleFrom, end: 1.0),
  );
  Animation<double> _out = _hidden;
  int? _outgoing;

  @override
  void didUpdateWidget(AppBranchSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    final index = widget.currentIndex;
    if (index == oldWidget.currentIndex) return;
    final duration = context.motion(AppBranchSwitcher.duration);
    if (duration == Duration.zero) {
      _controller.value = 1;
      _outgoing = null;
      return;
    }
    // A switch during a switch fades out whichever tab shows more.
    var outgoing = oldWidget.currentIndex;
    var from = _controller.isAnimating ? _in.value : 1.0;
    final previous = _outgoing;
    if (previous != null && previous != index && _out.value > from) {
      outgoing = previous;
      from = _out.value;
    }
    _outgoing = outgoing;
    _out = _controller.drive(
      Tween(
        begin: from,
        end: 0.0,
      ).chain(CurveTween(curve: Interval(0, _split, curve: Motion.exit))),
    );
    _controller
      ..duration = duration
      ..forward(from: 0);
  }

  void _onStatus(AnimationStatus status) {
    if (status.isCompleted && _outgoing != null) {
      setState(() => _outgoing = null);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      for (final (i, child) in widget.children.indexed) _branch(i, child),
    ],
  );

  Widget _branch(int index, Widget child) {
    final current = index == widget.currentIndex;
    final outgoing = index == _outgoing;
    return Offstage(
      offstage: !current && !outgoing,
      child: TickerMode(
        enabled: current,
        child: HeroMode(
          enabled: current,
          child: Inert(
            inert: !current,
            child: FadeTransition(
              opacity: current
                  ? _in
                  : outgoing
                  ? _out
                  : _hidden,
              child: ScaleTransition(
                scale: current ? _scale : _shown,
                child: RepaintBoundary(child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
