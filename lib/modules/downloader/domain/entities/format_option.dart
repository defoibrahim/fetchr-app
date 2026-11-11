import 'dart:math' as math;

import 'package:equatable/equatable.dart';

import '../../../../app/shared/domain/entities/quality.dart';

class FormatOption extends Equatable {
  const FormatOption({
    required this.quality,
    this.width,
    this.height,
    this.fps,
    this.sizeBytes,
    this.sizeIsEstimate = false,
  });

  final Quality quality;

  /// The produced file's dimensions; for [Quality.cover], the thumbnail's.
  final int? width;
  final int? height;
  final double? fps;
  final int? sizeBytes;
  final bool sizeIsEstimate;

  /// Orientation-proof: a 9:16 clip and a 16:9 one of the same quality agree.
  /// Null unless both sides are known; a lone width could be either side.
  int? get shortSide => switch ((width, height)) {
    (final w?, final h?) => math.min(w, h),
    _ => null,
  };

  @override
  List<Object?> get props => [
    quality,
    width,
    height,
    fps,
    sizeBytes,
    sizeIsEstimate,
  ];
}
