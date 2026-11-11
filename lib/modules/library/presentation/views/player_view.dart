import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';

import '../../../../app/routes/app_routes.dart';
import '../../../../app/shared/saved_source_provider.dart';
import '../../../../core/logging/app_logger.dart';
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
  final _videoKey = GlobalKey();
  VideoSurfaceBuilder? _video;
  bool _reported = false;

  @override
  void initState() {
    super.initState();
    _player = ref.read(playerFactoryProvider)();
    _errors = _player.stream.error.listen(_onError);
    unawaited(
      _player.open(Media(widget.uri)).catchError((Object e, StackTrace s) {
        _onError('$e');
      }),
    );
  }

  @override
  void dispose() {
    unawaited(_errors.cancel());
    unawaited(_player.dispose());
    super.dispose();
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
    return ColoredBox(color: _backdrop, child: video(context));
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
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.library);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = ref.watch(libraryItemProvider(widget.uri));
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
