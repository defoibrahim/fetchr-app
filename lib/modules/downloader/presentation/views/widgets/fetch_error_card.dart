import 'package:flutter/widgets.dart';

import '../../../../../app/shared/formatters/yt_dlp_formatter.dart';
import '../../../../../app/shared/yt_dlp_provider.dart';
import '../../../../../core/errors/failure.dart';
import '../../../../../core/gen/assets.gen.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/utils/formatters.dart';
import '../../../../../core/widgets/error_card.dart';

class FetchErrorActions {
  const FetchErrorActions({
    required this.updateYtDlp,
    required this.editLink,
    required this.anotherLink,
    required this.retry,
    required this.lowerQuality,
    required this.openLibrary,
  });

  final VoidCallback updateYtDlp,
      editLink,
      anotherLink,
      retry,
      lowerQuality,
      openLibrary;
}

/// The inline card for a failed fetch or a failed storage check. `storage`
/// wins over the failure type: the pre-check has no failure of its own.
ErrorCardData fetchErrorCard(
  Failure failure, {
  required FetchErrorActions actions,
  ({int needed, int free})? storage,
  YtDlpUpdatePhase ytDlpPhase = YtDlpUpdatePhase.idle,
}) {
  if (storage != null) return _storage(storage, actions);
  return switch (failure) {
    UnsupportedSiteFailure() => ErrorCardData(
      icon: Assets.icons.alertCircle,
      title: "This site isn't supported",
      body: const [
        TextSpan(
          text:
              "yt-dlp couldn't find a video at this link. Check the URL, or update yt-dlp — support for new sites lands often.",
        ),
      ],
      actions: [
        _updateYtDlp(actions, ytDlpPhase),
        _outlined('Edit link', actions.editLink),
      ],
    ),
    PrivateVideoFailure() => ErrorCardData(
      icon: Assets.icons.lock,
      title: 'This video is private',
      body: const [
        TextSpan(
          text:
              "Only people the uploader approved can watch it, so Fetchr can't download it.",
        ),
      ],
      actions: [_outlined('Try another link', actions.anotherLink)],
    ),
    NetworkFailure() => ErrorCardData(
      icon: Assets.icons.wifiOff,
      title: 'No internet connection',
      body: const [
        TextSpan(
          text:
              'Connect to Wi-Fi or mobile data and try again. Downloads already running will resume on their own.',
        ),
      ],
      actions: [_primary('Retry', actions.retry)],
    ),
    MediaUnavailableFailure() => ErrorCardData(
      icon: Assets.icons.alertCircle,
      title: "This video isn't available",
      body: const [
        TextSpan(
          text: "It may have been removed, or it's blocked where you are.",
        ),
      ],
      actions: [_outlined('Try another link', actions.anotherLink)],
    ),
    YtDlpBusyFailure() => ErrorCardData(
      icon: Assets.icons.refresh,
      title: 'yt-dlp is updating',
      body: const [TextSpan(text: 'Try again in a moment.')],
      actions: [_primary('Retry', actions.retry)],
    ),
    _ => ErrorCardData(
      icon: Assets.icons.alertCircle,
      title: "Couldn't get this video",
      body: const [
        TextSpan(text: 'yt-dlp reported an error. Updating it often helps.'),
      ],
      actions: [
        _updateYtDlp(actions, ytDlpPhase),
        _outlined('Edit link', actions.editLink),
      ],
    ),
  };
}

ErrorCardData _storage(
  ({int needed, int free}) storage,
  FetchErrorActions actions,
) => ErrorCardData(
  icon: Assets.icons.hardDrive,
  title: 'Not enough storage',
  body: [
    const TextSpan(text: 'This download needs about '),
    AppTextStyles.monoSpan(formatBytes(storage.needed)),
    const TextSpan(text: ' and '),
    AppTextStyles.monoSpan(formatBytes(storage.free)),
    const TextSpan(text: ' is free. Pick a lower quality or clear some space.'),
  ],
  actions: [
    _primary('Lower quality', actions.lowerQuality),
    _outlined('Open Library', actions.openLibrary),
  ],
);

/// Follows the update phase that Home and Settings share: "Check again" once
/// an update finished and the link still fails.
ErrorCardAction _updateYtDlp(
  FetchErrorActions actions,
  YtDlpUpdatePhase phase,
) => ErrorCardAction(
  label: phase.actionLabel,
  onPressed: actions.updateYtDlp,
  primary: true,
  busy: phase == YtDlpUpdatePhase.busy,
  busyLabel: ytDlpUpdatingLabel,
);

ErrorCardAction _primary(String label, VoidCallback onPressed) =>
    ErrorCardAction(label: label, onPressed: onPressed, primary: true);

ErrorCardAction _outlined(String label, VoidCallback onPressed) =>
    ErrorCardAction(label: label, onPressed: onPressed);
