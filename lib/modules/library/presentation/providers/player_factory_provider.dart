import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../../app/di/core_providers.dart';
import '../../../../core/logging/app_logger.dart';

/// The picture of a video for one player.
typedef VideoSurfaceBuilder = Widget Function(BuildContext context);

/// Everything that needs libmpv sits behind these two providers, so a test
/// replaces them and never loads it.
final playerFactoryProvider = Provider<Player Function()>(
  (ref) => () {
    // Loads libmpv; kept out of bootstrap so it does not delay the first frame.
    MediaKit.ensureInitialized();
    final player = Player();
    final api = ref.read(fetchrHostApiProvider);
    // Native detaches a tracked player if Android destroys the Activity while
    // it is open. Player.dispose awaits release before it frees the handle.
    unawaited(
      player.handle.then(api.trackPlayer).catchError((Object e) {
        AppLogger.warning('Could not track the player: $e');
      }),
    );
    player.platform?.release.add(
      () async => api.untrackPlayer(await player.handle),
    );
    return player;
  },
);

/// Binds a [VideoController] to the player once; every surface it builds, the
/// inline one and the fullscreen route, shows that one controller.
final videoSurfaceFactoryProvider =
    Provider<VideoSurfaceBuilder Function(Player player)>(
      (_) => (player) {
        final controller = VideoController(player);
        // Null is the package's NoVideoControls: PlayerControls draw on top.
        return (_) => Video(controller: controller, controls: null);
      },
    );
