import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/result.dart';
import '../../di/library_providers.dart';
import '../../domain/usecases/get_library_thumbnail_usecase.dart';

// 16:10 at twice the card's width, so the cached file stays sharp on dense
// screens. MediaThumb decodes it down to the box.
const _widthPx = 480;
const _heightPx = 300;

/// A cached JPEG path for the file's card, or null when it has no thumbnail or
/// the lookup failed: the card keeps its stripes either way, so a failure never
/// reaches the screen. The answer is kept for the session: scrolling a card
/// back into view would otherwise ask native again for a path, or a "none",
/// that cannot have changed. Only a failed lookup is retried on the next read.
final libraryThumbnailProvider = FutureProvider.autoDispose
    .family<String?, String>((ref, uri) async {
      final link = ref.keepAlive();
      final result = await ref.watch(getLibraryThumbnailUseCaseProvider)(
        ThumbnailParams(uri: uri, widthPx: _widthPx, heightPx: _heightPx),
      );
      if (result is Err) link.close();
      return result.valueOrNull;
    });
