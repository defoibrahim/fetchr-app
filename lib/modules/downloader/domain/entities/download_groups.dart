import 'package:equatable/equatable.dart';

import 'download_task.dart';

class DownloadGroups extends Equatable {
  const DownloadGroups({
    required this.active,
    required this.queued,
    required this.attention,
    required this.doneToday,
  });

  /// Running, paused and canceled, newest first.
  final List<DownloadTask> active;

  /// Oldest first: the next to run leads.
  final List<DownloadTask> queued;

  /// Failed, newest first.
  final List<DownloadTask> attention;

  /// Completed and finished today (local), newest first.
  final List<DownloadTask> doneToday;

  bool get isEmpty =>
      active.isEmpty &&
      queued.isEmpty &&
      attention.isEmpty &&
      doneToday.isEmpty;

  @override
  List<Object?> get props => [active, queued, attention, doneToday];
}
