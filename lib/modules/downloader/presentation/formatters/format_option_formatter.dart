import '../../../../app/shared/domain/entities/quality.dart';
import '../../../../core/utils/formatters.dart';
import '../../domain/entities/format_option.dart';

extension FormatOptionFormat on FormatOption {
  /// The line under the row's title: "MP4 · 1280×720 · 30 fps".
  String get detail {
    final dimensions = switch ((width, height)) {
      (final w?, final h?) => '$w×$h',
      _ => null,
    };
    final rate = switch (fps) {
      final value? when value > 0 => '${value.round()} fps',
      _ => null,
    };
    String known(String format, {required String fallback}) {
      final parts = [?dimensions, ?rate];
      return parts.isEmpty ? fallback : [format, ...parts].join(' · ');
    }

    return switch (quality) {
      Quality.best =>
        shortSide == null
            ? 'Video + audio merged'
            : '${shortSide}p · $dimensions',
      Quality.p1080 || Quality.p720 => known('MP4', fallback: 'MP4'),
      Quality.p480 => known('MP4', fallback: 'MP4 · data saver'),
      Quality.mp3 => 'MP3 · best quality (VBR)',
      Quality.cover => known('JPEG', fallback: 'JPEG'),
    };
  }

  /// "~184 MB" for an estimate, "184 MB" for an exact size.
  String get sizeText => switch (sizeBytes) {
    final bytes? => '${sizeIsEstimate ? '~' : ''}${formatBytes(bytes)}',
    _ => 'size unknown',
  };
}
