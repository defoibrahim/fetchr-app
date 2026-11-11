import 'package:equatable/equatable.dart';

import '../../../../core/errors/failure.dart';
import 'download_card_state.dart';
import 'download_request.dart';

enum TaskStatus { queued, running, completed, failed, canceled, paused }

/// What a running task is doing; the UI words it from this and the quality.
enum TaskStage { preparing, downloading, postProcessing }

class DownloadTask extends Equatable {
  const DownloadTask({
    required this.id,
    required this.request,
    required this.status,
    required this.progress,
    required this.createdAt,
    this.etaSec,
    this.failure,
    this.errorMessage,
    this.savedUri,
    this.stage = TaskStage.preparing,
    this.downloadedBytes,
    this.totalBytes,
    this.speedBytesPerSec,
    this.stalled = false,
    this.finishedAt,
  });

  final String id;
  final DownloadRequest request;
  final TaskStatus status;

  /// 0..1; below 0 when unknown (for example while merging).
  final double progress;
  final int? etaSec;
  final Failure? failure;

  /// The raw yt-dlp error line, for an `unknown` failure the user may report.
  final String? errorMessage;
  final String? savedUri;
  final DateTime createdAt;
  final TaskStage stage;
  final int? downloadedBytes;

  /// Null when yt-dlp does not know it.
  final int? totalBytes;

  /// Null until the first sample.
  final int? speedBytesPerSec;

  /// Running with no progress line for 30 s.
  final bool stalled;

  /// Set once the task completed, failed or was canceled.
  final DateTime? finishedAt;

  bool get isActive =>
      status == TaskStatus.queued || status == TaskStatus.running;

  bool get isPaused => status == TaskStatus.paused;

  DateTime get finishedOrCreatedAt => finishedAt ?? createdAt;

  /// The saved file, once the download has completed.
  String? get fileUri => status == TaskStatus.completed ? savedUri : null;

  DownloadCardState get cardState => switch (status) {
    TaskStatus.running => switch (stage) {
      TaskStage.preparing => DownloadCardState.preparing,
      TaskStage.downloading => DownloadCardState.downloading,
      TaskStage.postProcessing => DownloadCardState.merging,
    },
    TaskStatus.paused => DownloadCardState.paused,
    TaskStatus.queued => DownloadCardState.queued,
    TaskStatus.canceled => DownloadCardState.cancelled,
    TaskStatus.failed => DownloadCardState.failed,
    TaskStatus.completed => DownloadCardState.done,
  };

  @override
  List<Object?> get props => [
    id,
    request,
    status,
    progress,
    etaSec,
    failure,
    errorMessage,
    savedUri,
    createdAt,
    stage,
    downloadedBytes,
    totalBytes,
    speedBytesPerSec,
    stalled,
    finishedAt,
  ];
}
