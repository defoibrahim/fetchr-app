import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../../../../../core/gen/assets.gen.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/app_tokens.dart';
import '../../../../../core/theme/theme_extensions.dart';
import '../../../../../core/utils/formatters.dart';
import '../../../../../core/utils/scale.dart';
import '../../../../../core/widgets/app_icon.dart';

const _hideAfter = Duration(seconds: 3);
const _fade = Duration(milliseconds: 200);
const _seekStep = Duration(seconds: 10);

const _skipSize = 48.0;
const _playSize = 64.0;
const _skipIcon = 22.0;
const _playIcon = 24.0;
const _buttonGap = 36.0;
const _skipScrimAlpha = .45;
const _sidePad = 14.0;

/// The player's overlay on [child]: skip back and forward, play and pause, the
/// time, fullscreen and a seek bar. A tap shows or hides it, and it hides itself
/// 3 seconds after the last touch while playing; a double tap on a half seeks 10
/// seconds that way.
class PlayerControls extends StatefulWidget {
  const PlayerControls({
    super.key,
    required this.player,
    required this.child,
    required this.onFullscreen,
    this.isFullscreen = false,
  });

  final Player player;

  /// The picture the controls sit on.
  final Widget child;
  final VoidCallback onFullscreen;
  final bool isFullscreen;

  @override
  State<PlayerControls> createState() => _PlayerControlsState();
}

class _PlayerControlsState extends State<PlayerControls> {
  final _subscriptions = <StreamSubscription<Object?>>[];
  Timer? _hideTimer;
  var _visible = true;
  late bool _playing;
  late Duration _duration;

  // The player's latest position, always current for _seekTo and _skip.
  late Duration _position;

  // What the time label and the slider draw. It follows _position only while
  // the overlay is up or scrubbing, so a tick repaints those two and no more.
  late final ValueNotifier<Duration> _shown;

  /// Milliseconds under the thumb while it is held; null otherwise.
  double? _scrub;
  var _tapX = 0.0;

  @override
  void initState() {
    super.initState();
    final player = widget.player;
    _playing = player.state.playing;
    _position = player.state.position;
    _shown = ValueNotifier(_position);
    _duration = player.state.duration;
    final stream = player.stream;
    _subscriptions.addAll([
      stream.playing.listen((playing) {
        setState(() => _playing = playing);
        _restartTimer();
      }),
      stream.position.listen((value) {
        _position = value;
        if (_visible || _scrub != null) _shown.value = value;
      }),
      stream.duration.listen((value) => setState(() => _duration = value)),
    ]);
    _restartTimer();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _shown.dispose();
    super.dispose();
  }

  // Paused, the overlay stays up: there is nothing behind it to look at. Under
  // TalkBack it never hides: hidden controls leave the semantics tree, and the
  // tap layer that brings them back has no node to reach. Read from the
  // dispatcher, not MediaQuery, because initState calls this too.
  void _restartTimer() {
    _hideTimer?.cancel();
    final screenReader = WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .accessibleNavigation;
    if (!_visible || !_playing || screenReader) return;
    _hideTimer = Timer(_hideAfter, () => setState(() => _visible = false));
  }

  void _toggle() {
    setState(() => _visible = !_visible);
    if (_visible) _shown.value = _position;
    _restartTimer();
  }

  void _togglePlayback() {
    unawaited(widget.player.playOrPause());
    _restartTimer();
  }

  // The position moves at once rather than when the player reports it, so two
  // quick taps add up and the thumb does not jump back for a frame.
  void _seekTo(Duration target) {
    final end = _duration;
    final clamped = target < Duration.zero
        ? Duration.zero
        : end > Duration.zero && target > end
        ? end
        : target;
    unawaited(widget.player.seek(clamped));
    _position = clamped;
    _shown.value = clamped;
    setState(() => _scrub = null);
    _restartTimer();
  }

  void _skip(Duration step) => _seekTo(_position + step);

  void _onDoubleTap() {
    final width = context.size?.width ?? 0;
    _skip(_tapX < width / 2 ? -_seekStep : _seekStep);
  }

  // The tap and double tap sit on a layer behind the overlay, not around it: a
  // button inside a double-tap detector waits out the 300 ms double-tap window
  // before it fires.
  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        ExcludeSemantics(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggle,
            onDoubleTapDown: (details) => _tapX = details.localPosition.dx,
            onDoubleTap: _onDoubleTap,
          ),
        ),
        IgnorePointer(
          ignoring: !_visible,
          child: ExcludeSemantics(
            excluding: !_visible,
            child: AnimatedOpacity(
              opacity: _visible ? 1 : 0,
              duration: context.motion(_fade),
              curve: Curves.easeOut,
              child: _overlay(context),
            ),
          ),
        ),
      ],
    );
  }

  Widget _overlay(BuildContext context) {
    final tokens = context.tokens;
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: _buttonGap.w,
            children: [
              _skipButton(
                tokens,
                icon: Assets.icons.back10,
                tooltip: 'Back 10 seconds',
                step: -_seekStep,
              ),
              _playButton(tokens),
              _skipButton(
                tokens,
                icon: Assets.icons.forward10,
                tooltip: 'Forward 10 seconds',
                step: _seekStep,
              ),
            ],
          ),
        ),
        Positioned(left: 0, right: 0, bottom: 0, child: _bottomBar(context)),
      ],
    );
  }

  Widget _skipButton(
    AppTokens tokens, {
    required SvgGenImage icon,
    required String tooltip,
    required Duration step,
  }) => IconButton(
    tooltip: tooltip,
    onPressed: () => _skip(step),
    style: IconButton.styleFrom(
      backgroundColor: tokens.mediaScrim.withValues(alpha: _skipScrimAlpha),
      foregroundColor: tokens.onMedia,
      fixedSize: Size.square(_skipSize.r),
    ),
    icon: AppIcon(icon, size: _skipIcon.r),
  );

  // The filled button's icon is the one colour the light theme takes from the
  // accent, so it reads primaryIcon, not onPrimary.
  Widget _playButton(AppTokens tokens) => IconButton.filled(
    tooltip: _playing ? 'Pause' : 'Play',
    onPressed: _togglePlayback,
    style: IconButton.styleFrom(fixedSize: Size.square(_playSize.r)),
    icon: AppIcon(
      _playing ? Assets.icons.pause : Assets.icons.play,
      size: _playIcon.r,
      color: tokens.primaryIcon,
    ),
  );

  Widget _bottomBar(BuildContext context) {
    final tokens = context.tokens;
    final fullscreen = widget.isFullscreen;
    final length = _duration.inMilliseconds.toDouble();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: _sidePad.w),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ValueListenableBuilder<Duration>(
                valueListenable: _shown,
                builder: (context, position, _) {
                  final time = Duration(
                    milliseconds: _shownMs(position).round(),
                  );
                  return Text(
                    '${formatDuration(time.inSeconds)} / '
                    '${formatDuration(_duration.inSeconds)}',
                    style: context.type.monoSmall.copyWith(
                      color: tokens.onMedia,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  );
                },
              ),
              IconButton(
                tooltip: fullscreen ? 'Exit fullscreen' : 'Fullscreen',
                onPressed: widget.onFullscreen,
                style: IconButton.styleFrom(
                  foregroundColor: tokens.onMedia,
                  fixedSize: Size.square(AppSizes.touch.r),
                ),
                icon: AppIcon(
                  fullscreen
                      ? Assets.icons.fullscreenExit
                      : Assets.icons.fullscreen,
                  size: AppSizes.iconButton.r,
                ),
              ),
            ],
          ),
        ),
        // The thumb's overlay insets the track by 16 dp each side, so no side
        // padding here keeps the track near the text's edges.
        SizedBox(
          height: AppSizes.touch.r,
          child: ValueListenableBuilder<Duration>(
            valueListenable: _shown,
            builder: (context, position, _) => Slider(
              value: _shownMs(position).clamp(0, length > 0 ? length : 1),
              max: length > 0 ? length : 1,
              onChangeStart: length > 0 ? (_) => _hideTimer?.cancel() : null,
              onChanged: length > 0
                  ? (value) => setState(() => _scrub = value)
                  : null,
              onChangeEnd: length > 0
                  ? (value) => _seekTo(Duration(milliseconds: value.round()))
                  : null,
              semanticFormatterCallback: (value) =>
                  formatDuration(value ~/ 1000),
            ),
          ),
        ),
      ],
    );
  }

  double _shownMs(Duration position) =>
      _scrub ?? position.inMilliseconds.toDouble();
}
