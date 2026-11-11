import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../core/errors/failure.dart';
import '../../../../../core/gen/assets.gen.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/utils/scale.dart';
import '../../../../../core/widgets/app_icon_button.dart';
import '../../../../../core/widgets/app_snackbar.dart';
import '../../../../../core/widgets/confirm_dialog.dart';
import '../../../../../core/widgets/error_card.dart';
import '../../../domain/entities/download_task.dart';
import '../../formatters/download_task_formatter.dart';

/// A failed download: the media title, why it failed, Retry (or Open settings
/// when the app may not write files) and Remove. For an unknown failure, a tap
/// on the row shows the raw yt-dlp line.
class AttentionRow extends StatelessWidget {
  const AttentionRow({
    super.key,
    required this.task,
    required this.onRetry,
    required this.onOpenSettings,
    required this.onRemove,
  });

  final DownloadTask task;
  final VoidCallback onRetry;
  final VoidCallback onOpenSettings;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final denied = task.failure is StoragePermissionFailure;
    final line = _rawLine(task);
    final card = ErrorCard(
      layout: ErrorCardLayout.compact,
      data: ErrorCardData(
        icon: Assets.icons.alertCircle,
        title: task.request.title,
        body: [TextSpan(text: task.failureReason)],
        actions: [
          ErrorCardAction(
            label: denied ? 'Open settings' : 'Retry',
            onPressed: denied ? onOpenSettings : onRetry,
            primary: true,
          ),
        ],
      ),
    );
    return Row(
      spacing: Gap.sm.w,
      children: [
        Expanded(
          child: line == null
              ? card
              : Semantics(
                  onTapHint: 'Show error details',
                  child: GestureDetector(
                    onTap: () => showRawErrorDialog(context, line),
                    child: card,
                  ),
                ),
        ),
        AppIconButton(
          icon: Assets.icons.close,
          tooltip: 'Remove',
          onPressed: onRemove,
          bordered: true,
        ),
      ],
    );
  }

  /// The yt-dlp line, only when nothing better explains the failure.
  static String? _rawLine(DownloadTask task) {
    final line = task.errorMessage;
    return task.failure is UnexpectedFailure && line != null && line.isNotEmpty
        ? line
        : null;
  }
}

/// The raw yt-dlp line for a user who wants to report it. Copy puts it on the
/// clipboard and says so.
Future<void> showRawErrorDialog(BuildContext context, String line) async {
  final copied = await showDialog<bool>(
    context: context,
    builder: (_) => _RawErrorDialog(line: line),
  );
  if (copied != true || !context.mounted) return;
  await Clipboard.setData(ClipboardData(text: line));
  if (!context.mounted) return;
  AppSnackbar.show(context, 'Copied', type: SnackType.success);
}

class _RawErrorDialog extends StatelessWidget {
  const _RawErrorDialog({required this.line});

  final String line;

  @override
  Widget build(BuildContext context) {
    final dialog = DialogTheme.of(context);
    return Dialog(
      child: Padding(
        padding: EdgeInsets.all(Gap.xl.r),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Gap.lg.h,
          children: [
            Text('Download failed', style: dialog.titleTextStyle),
            Flexible(
              child: SingleChildScrollView(
                child: MonoPanel(child: SelectableText(line)),
              ),
            ),
            DialogActions(
              cancelLabel: 'Close',
              confirmLabel: 'Copy',
              onConfirm: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      ),
    );
  }
}
