import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';

import '../../../../app/routes/app_routes.dart';
import '../../../../app/shared/saved_source_provider.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/theme/app_motion.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/theme_extensions.dart';
import '../../../../core/utils/scale.dart';
import '../../../../core/widgets/app_back_button.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../core/widgets/centered_content.dart';
import '../../../../core/widgets/media_thumb.dart';
import '../../domain/entities/library_item.dart';
import '../providers/library_item_provider.dart';
import '../providers/library_notifier.dart';
import '../providers/player_factory_provider.dart';
import 'widgets/delete_library_item.dart';
import 'widgets/player_controls.dart';
import 'widgets/player_details.dart';

const _mediaAspect = 16 / 9;
const _audioIconSize = 56.0;

// A video frame is letterboxed in black in both themes.
const _backdrop = Colors.black;

class PlayerView extends ConsumerStatefulWidget {
  const PlayerView({super.key, required this.uri, required this.title});

  final String uri;
  final String title;

  @override
  ConsumerState<PlayerView> createState() => _PlayerViewState();
}

class _PlayerViewState extends ConsumerState<PlayerView> {
  late final Player _player;
  late final StreamSubscription<String> _errors;
  late final AppLifecycleListener _lifecycle;
  final _videoKey = GlobalKey();
  VideoSurfaceBuilder? _video;
  bool _reported = false;

  // What the page last showed, kept once it starts leaving: the delete that
  // follows hides the item while the route still fades out, and the page must
  // not turn into a black box (or bind a video controller to an audio file)
  // under the user's eyes.
  LibraryItem? _shown;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _player = ref.read(playerFactoryProvider)();
    _errors = _player.stream.error.listen(_onError);
    _lifecycle = AppLifecycleListener(onHide: _pauseVideo);
    unawaited(
      _player.open(Media(widget.uri)).catchError((Object e, StackTrace s) {
        _onError('$e');
      }),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    unawaited(_errors.cancel());
    unawaited(_player.dispose());
    super.dispose();
  }

  // Nobody sees a video in the background, and libmpv drawing into a surface
  // whose Activity Android then destroys crashed the app. Audio keeps playing.
  // A file the Library does not list (another folder, or still loading) is
  // judged by what mpv found in it; cover art does not make a song a video.
  void _pauseVideo() {
    final isAudio =
        ref.read(libraryItemProvider(widget.uri))?.isAudio ??
        !_player.state.tracks.video.any(
          (t) => t.id != 'auto' && t.id != 'no' && t.albumart != true,
        );
    if (!isAudio) unawaited(_player.pause());
  }

  // mpv logs decoder errors that do not stop playback, so the video stays up
  // and the user is told once.
  void _onError(String message) {
    AppLogger.warning('Playback error: $message');
    if (_reported || !mounted) return;
    _reported = true;
    AppSnackbar.show(
      context,
      "Couldn't play this file properly.",
      type: SnackType.error,
    );
  }

  // Built once, on the first video: an audio file never binds a controller.
  Widget _surface(BuildContext context, {required bool isAudio}) {
    if (isAudio) return const AudioTile(iconSize: _audioIconSize);
    final video = _video ??= ref.read(videoSurfaceFactoryProvider)(_player);
    return ColoredBox(
      color: _backdrop,
      child: _FirstFrameFade(player: _player, child: video(context)),
    );
  }

  // Restored in finally: the route can end by the system back button too.
  Future<void> _enterFullscreen() async {
    final isAudio = ref.read(libraryItemProvider(widget.uri))?.isAudio ?? false;
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    try {
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (route) => Scaffold(
            backgroundColor: _backdrop,
            body: PlayerControls(
              player: _player,
              isFullscreen: true,
              onFullscreen: () => Navigator.of(route).pop(),
              child: _surface(route, isAudio: isAudio),
            ),
          ),
        ),
      );
    } finally {
      await SystemChrome.setPreferredOrientations(const []);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  Future<void> _share(LibraryItem item) async {
    await AppSnackbar.showFailure(
      context,
      ref.read(libraryNotifierProvider.notifier).share(item),
    );
  }

  // With nothing under the player (a deep link), the Library is the place a
  // deleted file leaves you.
  void _leave() {
    _leaving = true;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.library);
    }
  }

  @override
  Widget build(BuildContext context) {
    final watched = ref.watch(libraryItemProvider(widget.uri));
    final item = _leaving ? _shown : (_shown = watched);
    // The key moves the picture between the stacked and split layouts without
    // rebuilding its Element, so a rotation keeps the overlay and the texture.
    final video = KeyedSubtree(
      key: _videoKey,
      child: AspectRatio(
        aspectRatio: _mediaAspect,
        child: PlayerControls(
          player: _player,
          onFullscreen: () => unawaited(_enterFullscreen()),
          child: _surface(context, isAudio: item?.isAudio ?? false),
        ),
      ),
    );
    final details = PlayerDetails(
      title: item?.name ?? widget.title,
      source: ref.watch(savedSourceProvider(widget.uri)),
      item: item,
      onShare: (file) => unawaited(_share(file)),
      onDelete: (file) =>
          unawaited(deleteLibraryItem(context, ref, file, onConfirmed: _leave)),
    );
    final split = context.windowClass.isAtLeast(WindowClass.expanded);
    return Scaffold(
      body: SafeArea(
        child: split
            ? Column(
                children: [
                  const _BackRow(),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Three parts of five for the picture.
                        Expanded(flex: 3, child: video),
                        Expanded(
                          flex: 2,
                          child: SingleChildScrollView(child: details),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : SingleChildScrollView(
                child: CenteredContent(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [const _BackRow(), video, details],
                  ),
                ),
              ),
      ),
    );
  }
}

class _BackRow extends StatelessWidget {
  const _BackRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(Gap.sm.w, Gap.xs.h, Gap.sm.w, Gap.sm.h),
      child: Row(
        spacing: Gap.xs.w,
        children: [
          const AppBackButton(),
          // The button already says Back to a screen reader.
          ExcludeSemantics(child: Text('Back', style: context.type.button)),
        ],
      ),
    );
  }
}

/// Fades [child] in over the black backdrop once the player knows the video's
/// size, which it learns with the first frame; the surface would otherwise pop
/// in. A player that already has a frame (the fullscreen route) shows at once.
class _FirstFrameFade extends StatefulWidget {
  const _FirstFrameFade({required this.player, required this.child});

  final Player player;
  final Widget child;

  @override
  State<_FirstFrameFade> createState() => _FirstFrameFadeState();
}

class _FirstFrameFadeState extends State<_FirstFrameFade> {
  late bool _hasFrame = widget.player.state.width != null;
  StreamSubscription<int?>? _width;

  @override
  void initState() {
    super.initState();
    if (_hasFrame) return;
    _width = widget.player.stream.width.listen((width) {
      if (width == null || !mounted) return;
      unawaited(_width?.cancel());
      _width = null;
      setState(() => _hasFrame = true);
    });
  }

  @override
  void dispose() {
    unawaited(_width?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
    opacity: _hasFrame ? 1 : 0,
    duration: context.motion(Motion.base),
    curve: Motion.enter,
    child: widget.child,
  );
}
