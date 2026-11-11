import '../../../../app/shared/domain/entities/quality.dart';

extension QualityFormat on Quality {
  /// The title of the sheet's row.
  String get optionLabel => switch (this) {
    Quality.best => 'Best available',
    Quality.p1080 => '1080p',
    Quality.p720 => '720p',
    Quality.p480 => '480p',
    Quality.mp3 => 'Audio only',
    Quality.cover => 'Cover photo',
  };

  /// The sheet's button, "Download 720p". Best and Cover read lowercase there,
  /// as the design's copy has them; everywhere else they are the pill labels.
  String get downloadLabel => switch (this) {
    Quality.best || Quality.cover => 'Download ${shortLabel.toLowerCase()}',
    _ => 'Download $shortLabel',
  };

  /// "720p · MP4", "MP3" or "Cover · JPG".
  String get formatLabel => switch (this) {
    Quality.mp3 => shortLabel,
    Quality.cover => '$shortLabel · JPG',
    _ => '$shortLabel · MP4',
  };
}
