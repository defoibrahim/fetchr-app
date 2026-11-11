import '../../../core/utils/dates.dart';
import '../../../core/utils/formatters.dart';
import '../domain/entities/yt_dlp_status.dart';
import '../yt_dlp_provider.dart';

/// Home's error card and Settings show the same update button.
const ytDlpUpdatingLabel = 'Updating…';

extension YtDlpStatusFormat on YtDlpStatus {
  /// "yt-dlp 2026.08.19", or "yt-dlp bundled" before native reports a version.
  String get versionLabel => 'yt-dlp ${version ?? 'bundled'}';
}

extension YtDlpUpdatePhaseFormat on YtDlpUpdatePhase {
  /// "Check again" once an update finished and the problem is still there.
  String get actionLabel =>
      this == YtDlpUpdatePhase.done ? 'Check again' : 'Update yt-dlp';
}

/// The caption under the version, or null when there is nothing to say: idle
/// with no status read yet. Only an idle phase reads the clock.
String? ytDlpCaption(
  YtDlpStatus? status,
  YtDlpUpdatePhase phase,
  DateTime now,
) => switch (phase) {
  YtDlpUpdatePhase.busy => 'Downloading the latest release…',
  YtDlpUpdatePhase.done => 'Updated just now',
  YtDlpUpdatePhase.idle => status == null ? null : _lastChecked(status, now),
};

String _lastChecked(YtDlpStatus status, DateTime now) {
  final checked = status.checkedAt;
  if (checked == null) return 'Never checked';
  final at = checked.toLocal();
  final day = localDay(at);
  final today = localDay(now);
  // DateTime normalises day 0 to the last day of the previous month.
  final yesterday = DateTime(today.year, today.month, today.day - 1);
  if (day == today) return 'Last checked today, ${formatClock(at)}';
  if (day == yesterday) return 'Last checked yesterday, ${formatClock(at)}';
  return 'Last checked ${at.day} ${shortMonth(at.month)}';
}
