import 'dart:math' as math;

import 'package:equatable/equatable.dart';

class LibraryItem extends Equatable {
  const LibraryItem({
    required this.uri,
    required this.name,
    required this.mimeType,
    required this.isAudio,
    required this.sizeBytes,
    required this.dateAdded,
    this.durationMs,
    this.width,
    this.height,
    this.relativePath,
  });

  final String uri;
  final String name;
  final String mimeType;
  final bool isAudio;
  final int sizeBytes;
  final int? durationMs;
  final DateTime dateAdded;
  final int? width;
  final int? height;

  /// Where the file sits under its volume, for example `Movies/Fetchr/`.
  final String? relativePath;

  /// Orientation-proof: a 9:16 clip and a 16:9 one of the same quality agree.
  /// Null unless both sides are known; a lone width could be either side.
  int? get shortSide => switch ((width, height)) {
    (final w?, final h?) => math.min(w, h),
    _ => null,
  };

  @override
  List<Object?> get props => [
    uri,
    name,
    mimeType,
    isAudio,
    sizeBytes,
    durationMs,
    dateAdded,
    width,
    height,
    relativePath,
  ];
}
