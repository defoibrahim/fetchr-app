import 'package:flutter/material.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/utils/scale.dart';
import '../../../../../core/widgets/media_thumb.dart';
import '../../../domain/entities/download_task.dart';

/// A task's 64 x 38 thumbnail. The playlist rows use the same size.
class DownloadThumb extends StatelessWidget {
  const DownloadThumb({super.key, required this.task, this.dimmed = false});

  static const width = 64.0;
  static const height = 38.0;

  final DownloadTask task;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    return MediaThumb(
      image: networkThumb(task.request.thumbnail),
      width: width.w,
      height: height.h,
      radius: Radii.thumbSmall,
      isAudio: task.request.quality.isAudio,
      dimmed: dimmed,
    );
  }
}
