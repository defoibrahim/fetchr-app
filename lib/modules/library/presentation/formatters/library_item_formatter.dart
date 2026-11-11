import '../../../../core/utils/formatters.dart';
import '../../domain/entities/library_item.dart';

extension LibraryItemFormat on LibraryItem {
  /// "1080p", "720p", "MP3", or "Video" when the dimensions are not known.
  String get qualityLabel {
    if (isAudio) return 'MP3';
    final side = shortSide;
    return side == null ? 'Video' : '${side}p';
  }

  /// "1080p · 184 MB", "MP3 · 6.2 MB".
  String get metaText => '$qualityLabel · ${formatBytes(sizeBytes)}';

  /// "MP4", "MP3": the file extension, or the mime subtype without one.
  String get containerLabel {
    final dot = name.lastIndexOf('.');
    final extension = dot < 0 ? '' : name.substring(dot + 1);
    return (extension.isEmpty ? mimeType.split('/').last : extension)
        .toUpperCase();
  }

  /// "1080p · MP4", or "MP3" alone, where the quality already is the
  /// container.
  String get formatLabel {
    final quality = qualityLabel;
    final container = containerLabel;
    return quality == container ? quality : '$quality · $container';
  }

  /// "{relativePath}{name}", for example "Movies/Fetchr/Desert drive.mp4".
  String get location {
    final folder = relativePath ?? '';
    final separator = folder.isEmpty || folder.endsWith('/') ? '' : '/';
    return '$folder$separator$name';
  }
}
