import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// The picture of a video for one player.
typedef VideoSurfaceBuilder = Widget Function(BuildContext context);

/// Everything that needs libmpv sits behind these two providers, so a test
/// replaces them and never loads it.
final playerFactoryProvider = Provider<Player Function()>(
  (_) => () {
    // Loads libmpv; kept out of bootstrap so it does not delay the first frame.
    MediaKit.ensureInitialized();
    return Player();
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
