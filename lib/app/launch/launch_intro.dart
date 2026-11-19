import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/gen/assets.gen.dart';
import '../../core/logging/app_logger.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/app_icon.dart';
import '../shared/launch_logo_target.dart';
import '../theme/system_bars.dart';

/// Raw logical pixels, not `.r`: the native splash draws this tile in dp.
const _logoSide = 120.0;
// The Home header tile's proportions, so the flight lands on an identical tile.
const _radiusShare = Radii.logo / AppSizes.logoTile;
const _glyphShare = AppSizes.logoGlyph / AppSizes.logoTile;
const _tagline = ['Any ', 'link. ', 'Any ', 'format.'];
const _taglineGap = 28.0;
const _wordRise = 10.0;
const _wordIn = Duration(milliseconds: 280);
const _wordStagger = Duration(milliseconds: 80);
// Long enough to read the line before the tile leaves.
const _taglineHold = Duration(milliseconds: 400);
const _taglineOut = Duration(milliseconds: 250);

/// From the native splash being gone to the tile leaving the centre.
@visibleForTesting
final launchIntroReveal =
    _wordStagger * (_tagline.length - 1) + _wordIn + _taglineHold;
@visibleForTesting
const launchIntroFlight = Duration(milliseconds: 750);
@visibleForTesting
const launchIntroFade = Duration(milliseconds: 250);
// The system hands the splash over a fraction of a second after the first
// frame, and never later than 2 s after asking. This bounds the dead time when
// it never does, because no splash was shown.
@visibleForTesting
const launchIntroSplashTimeout = Duration(milliseconds: 1200);
@visibleForTesting
const launchIntroOverlayKey = ValueKey('launch-intro-overlay');

/// Whether the app opened on a route of its own, such as a notification's
/// fetchr://app/downloads: the intro would cover that screen and find no Home
/// header to land on, so the app starts without it.
bool launchedOnDeepLink(String initialRoute) =>
    initialRoute != Navigator.defaultRouteName;

/// The colours of the native launch splash, which Android resolves from
/// `values/colors.xml` and `values-night/colors.xml` by the system's
/// brightness: the Home header tile in the default accent. A test keeps the
/// two copies equal.
({Color background, Color tile, Color glyph}) launchSplashColors(
  Brightness brightness,
) {
  final theme = brightness == Brightness.dark
      ? AppTheme.dark()
      : AppTheme.light();
  final tokens = theme.extension<AppTokens>()!;
  return (
    background: tokens.bg,
    tile: theme.colorScheme.primary,
    glyph: tokens.primaryIcon,
  );
}

/// Paints the native splash's last frame over the app, waits for the native
/// splash to be gone, shows the tagline, then flies the tile onto the Home
/// header's logo tile while the colours settle into the in-app theme.
class LaunchIntro extends StatefulWidget {
  const LaunchIntro({super.key, required this.splashGone, required this.child});

  final Future<void> Function() splashGone;
  final Widget child;

  @override
  State<LaunchIntro> createState() => _LaunchIntroState();
}

class _LaunchIntroState extends State<LaunchIntro>
    with SingleTickerProviderStateMixin {
  final _tileKey = GlobalKey();
  late final _controller = AnimationController(vsync: this);
  Rect? _target;
  bool _started = false;
  bool _done = false;

  Duration get _flight => _target == null ? Duration.zero : launchIntroFlight;

  @override
  void initState() {
    super.initState();
    // After the first frame, so the timeout counts from when the user sees it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_run());
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    try {
      await widget.splashGone().timeout(launchIntroSplashTimeout);
    } on TimeoutException {
      AppLogger.warning('The native splash did not report in time');
    } catch (e, s) {
      AppLogger.error('Could not wait for the native splash', e, s);
    }
    // A tap or a shared link may have moved it on while it waited.
    if (!mounted || _done || _started) return;
    if (context.reduceMotion) return _finish();
    _start();
    _play();
  }

  void _start() {
    _target = _targetRect();
    _controller.duration = launchIntroReveal + _flight + launchIntroFade;
    _started = true;
  }

  // Never completes once disposed or stopped, so no mounted check is needed
  // and a jump to the fade does not finish twice.
  void _play() => unawaited(_controller.forward().then((_) => _finish()));

  /// A tap: straight to the closing fade, with the tile already home, even
  /// before the native splash has reported.
  void _skipToFade() {
    if (_done) return;
    if (context.reduceMotion) return _finish();
    if (!_started) _start();
    final total = _controller.duration!.inMicroseconds;
    final fade = (launchIntroReveal + _flight).inMicroseconds / total;
    if (_controller.value >= fade) return;
    _controller.value = fade;
    _play();
  }

  /// A shared link opens a sheet the intro would cover: gone at once.
  void _skip() {
    if (!_done && mounted) _finish();
  }

  /// The header tile's rect in this widget's coordinates, or null when the
  /// header is not on screen (another route opened first).
  Rect? _targetRect() {
    final tile = _tileKey.currentContext?.findRenderObject();
    final self = context.findRenderObject();
    if (tile is! RenderBox || self is! RenderBox) return null;
    if (!tile.attached || !tile.hasSize || tile.size.isEmpty) return null;
    return tile.localToGlobal(Offset.zero, ancestor: self) & tile.size;
  }

  void _finish() => setState(() => _done = true);

  double _phase(Duration start, Duration length) {
    final total = _controller.duration ?? Duration.zero;
    final now = _controller.value * total.inMicroseconds;
    return ((now - start.inMicroseconds) / length.inMicroseconds).clamp(
      0.0,
      1.0,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LaunchLogoTarget(
      tileKey: _tileKey,
      skipIntro: _skip,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (!_done)
            AnimatedBuilder(animation: _controller, builder: _overlay),
        ],
      ),
    );
  }

  Widget _overlay(BuildContext context, Widget? _) {
    final target = _target;
    final flight = target == null
        ? 0.0
        : Curves.easeInOutCubic.transform(
            _phase(launchIntroReveal, launchIntroFlight),
          );
    final fade = Curves.easeOut.transform(
      _phase(launchIntroReveal + _flight, launchIntroFade),
    );
    // The system's brightness, not the in-app mode: it is what the native
    // splash was resolved with.
    final platform = MediaQuery.platformBrightnessOf(context);
    final start = launchSplashColors(platform);
    final tokens = context.tokens;
    final background = Color.lerp(start.background, tokens.bg, flight)!;
    final centre = Rect.fromCenter(
      center: MediaQuery.sizeOf(context).center(Offset.zero),
      width: _logoSide,
      height: _logoSide,
    );
    final iconsOnBackground =
        ThemeData.estimateBrightnessForColor(background) == Brightness.dark
        ? Brightness.light
        : Brightness.dark;
    // Nothing under it takes a touch, and the first one ends the show.
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => _skipToFade(),
      child: AbsorbPointer(
        key: launchIntroOverlayKey,
        child: ExcludeSemantics(
          child: AnnotatedRegion(
            value: systemBarsStyle(iconsOnBackground),
            // The overlay sits above the Navigator, outside any screen's
            // Material, so its text would get the debug underline without one.
            child: Material(
              type: MaterialType.transparency,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: background.withValues(alpha: 1 - fade)),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: centre.bottom + _taglineGap,
                    child: _taglineLine(
                      context,
                      AppPalette.of(platform).text,
                      1 - _phase(launchIntroReveal, _taglineOut),
                    ),
                  ),
                  _tile(
                    rect: Rect.lerp(centre, target ?? centre, flight)!,
                    color: Color.lerp(
                      start.tile,
                      context.colors.primary,
                      flight,
                    )!,
                    glyph: Color.lerp(start.glyph, tokens.primaryIcon, flight)!,
                    // On the header's tile the overlay's tile only hides, once
                    // the background is gone. With nowhere to land it fades too.
                    opacity: target == null ? 1 - fade : 1,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tile({
    required Rect rect,
    required Color color,
    required Color glyph,
    required double opacity,
  }) => Positioned.fromRect(
    rect: rect,
    child: Opacity(
      opacity: opacity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(rect.width * _radiusShare),
        ),
        child: Center(
          child: AppIcon(
            Assets.icons.logo,
            size: rect.width * _glyphShare,
            color: glyph,
          ),
        ),
      ),
    ),
  );

  /// The tagline, each word rising into place after the one before it.
  Widget _taglineLine(BuildContext context, Color color, double visible) {
    final style = context.type.section.copyWith(color: color);
    return Wrap(
      alignment: WrapAlignment.center,
      children: [
        for (final (i, word) in _tagline.indexed)
          _word(word, i, style, visible),
      ],
    );
  }

  Widget _word(String text, int index, TextStyle style, double visible) {
    final shown = Curves.easeOutCubic.transform(
      _phase(_wordStagger * index, _wordIn),
    );
    return Opacity(
      opacity: shown * visible,
      child: Transform.translate(
        offset: Offset(0, (1 - shown) * _wordRise),
        child: Text(text, style: style),
      ),
    );
  }
}
