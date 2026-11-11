import 'package:flutter/material.dart';

import '../../core/errors/failure.dart';
import '../../core/errors/failure_mapper.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/scale.dart';
import '../../core/widgets/error_card.dart';
import '../../modules/downloader/domain/entities/download_request.dart';
import '../../modules/downloader/domain/entities/download_task.dart';
import '../../modules/downloader/domain/entities/format_option.dart';
import '../../modules/downloader/presentation/views/widgets/attention_row.dart';
import '../../modules/downloader/presentation/views/widgets/download_card.dart';
import '../../modules/downloader/presentation/views/widgets/fetch_error_card.dart';
import '../../modules/downloader/presentation/views/widgets/quality_option.dart';
import '../../modules/downloader/presentation/views/widgets/url_field.dart';
import '../../modules/library/domain/entities/library_item.dart';
import '../../modules/library/presentation/views/widgets/library_card.dart';
import '../shared/domain/entities/quality.dart';
import 'gallery_section.dart';

const _mb = 1024 * 1024;
const _libraryCardWidth = 160.0;
const _link = 'https://youtube.com/watch?v=Qx7mT0aK3pE';
final _created = DateTime(2026, 10, 15, 9);

const _actions = FetchErrorActions(
  updateYtDlp: noop,
  editLink: noop,
  anotherLink: noop,
  retry: noop,
  lowerQuality: noop,
  openLibrary: noop,
);

DownloadTask _task(
  String label, {
  TaskStatus status = TaskStatus.running,
  TaskStage stage = TaskStage.downloading,
  Quality quality = Quality.p1080,
  double progress = 0.64,
  int? total = 184 * _mb,
  bool stalled = false,
  Failure? failure,
  String? errorMessage,
}) => DownloadTask(
  id: label,
  request: DownloadRequest(
    url: _link,
    title: 'Desert drive at golden hour · $label',
    quality: quality,
    folder: 'Fetchr',
    useAria2c: false,
    durationSec: 754,
  ),
  status: status,
  progress: progress,
  createdAt: _created,
  stage: stage,
  downloadedBytes: progress < 0 ? 42 * _mb : (184 * _mb * progress).round(),
  totalBytes: total,
  speedBytesPerSec: stalled ? null : 4 * _mb,
  etaSec: 16,
  stalled: stalled,
  failure: failure,
  errorMessage: errorMessage,
);

/// The URL field's four borders, pinned so they show without a focus.
class UrlFieldSection extends StatefulWidget {
  const UrlFieldSection({super.key});

  @override
  State<UrlFieldSection> createState() => _UrlFieldSectionState();
}

class _UrlFieldSectionState extends State<UrlFieldSection> {
  final _fields = {
    for (final state in UrlFieldState.values)
      state: (
        TextEditingController(text: state == UrlFieldState.empty ? '' : _link),
        FocusNode(),
      ),
  };

  @override
  void dispose() {
    for (final (controller, focus) in _fields.values) {
      controller.dispose();
      focus.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GallerySection(
      title: 'URL field',
      children: [
        for (final MapEntry(key: state, value: (controller, focus))
            in _fields.entries)
          GalleryExample(
            label: state.name,
            child: UrlField(
              controller: controller,
              focusNode: focus,
              onPaste: noop,
              onClear: noop,
              state: state,
            ),
          ),
      ],
    );
  }
}

class QualityOptionsSection extends StatelessWidget {
  const QualityOptionsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return const GallerySection(
      title: 'Quality options',
      children: [
        GalleryExample(
          label: 'selected, exact size',
          child: QualityOption(
            option: FormatOption(
              quality: Quality.p1080,
              width: 1920,
              height: 1080,
              fps: 60,
              sizeBytes: 184 * _mb,
            ),
            selected: true,
            onTap: noop,
          ),
        ),
        GalleryExample(
          label: 'not selected, estimated size',
          child: QualityOption(
            option: FormatOption(
              quality: Quality.mp3,
              sizeBytes: 11 * _mb,
              sizeIsEstimate: true,
            ),
            selected: false,
            onTap: noop,
          ),
        ),
      ],
    );
  }
}

class FetchErrorsSection extends StatelessWidget {
  const FetchErrorsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final cards = [
      for (final failure in const <Failure>[
        UnsupportedSiteFailure(),
        PrivateVideoFailure(),
        MediaUnavailableFailure(),
        NetworkFailure(),
        YtDlpBusyFailure(),
        UnexpectedFailure(),
      ])
        (
          failure.runtimeType.toString(),
          fetchErrorCard(failure, actions: _actions),
        ),
      (
        'storage pre-check',
        fetchErrorCard(
          const StorageFailure(),
          actions: _actions,
          storage: (needed: 184 * _mb, free: 96 * _mb),
        ),
      ),
    ];
    return GallerySection(
      title: 'Fetch errors',
      children: [
        for (final (label, data) in cards)
          GalleryExample(
            label: label,
            child: ErrorCard(data: data),
          ),
      ],
    );
  }
}

class DownloadCardsSection extends StatelessWidget {
  const DownloadCardsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final tasks = [
      _task('preparing', stage: TaskStage.preparing, progress: -1, total: null),
      _task('downloading'),
      _task('size unknown', progress: -1, total: null),
      _task('waiting for network', stalled: true),
      _task('merging', stage: TaskStage.postProcessing, progress: -1),
      _task(
        'converting',
        stage: TaskStage.postProcessing,
        quality: Quality.mp3,
        progress: -1,
      ),
      _task('paused', status: TaskStatus.paused, progress: 0.41),
      _task('cancelled', status: TaskStatus.canceled, progress: 0.41),
    ];
    return GallerySection(
      title: 'Download cards',
      children: [
        for (final task in tasks)
          GalleryExample(
            label: task.id,
            child: DownloadCard(
              task: task,
              onPause: noop,
              onResume: noop,
              onCancel: noop,
              onRestart: noop,
              onRemove: noop,
            ),
          ),
      ],
    );
  }
}

/// One compact row per native error code.
class AttentionRowsSection extends StatelessWidget {
  const AttentionRowsSection({super.key});

  @override
  Widget build(BuildContext context) {
    const codes = [
      'unsupported_site',
      'private_video',
      'unavailable',
      'network',
      'no_storage',
      'permission_denied',
      'busy',
      'unknown',
    ];
    return GallerySection(
      title: 'Failed downloads',
      children: [
        for (final code in codes)
          GalleryExample(
            label: code,
            child: AttentionRow(
              task: _task(
                code,
                status: TaskStatus.failed,
                progress: 0.41,
                failure: failureFromCode(code),
                errorMessage: code == 'unknown'
                    ? 'ERROR: [generic] Unable to extract video data'
                    : null,
              ),
              onRetry: noop,
              onOpenSettings: noop,
              onRemove: noop,
            ),
          ),
      ],
    );
  }
}

class LibraryCardsSection extends StatelessWidget {
  const LibraryCardsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final width = _libraryCardWidth.w;
    final items = [
      LibraryItem(
        uri: 'content://gallery/video',
        name: 'Desert drive at golden hour.mp4',
        mimeType: 'video/mp4',
        isAudio: false,
        sizeBytes: 96 * _mb,
        dateAdded: _created,
        durationMs: 754000,
        width: 1920,
        height: 1080,
        relativePath: 'Movies/Fetchr/',
      ),
      LibraryItem(
        uri: 'content://gallery/audio',
        name: 'Night radio session.mp3',
        mimeType: 'audio/mpeg',
        isAudio: true,
        sizeBytes: 11 * _mb,
        dateAdded: _created,
        durationMs: 221000,
        relativePath: 'Music/Fetchr/',
      ),
    ];
    return GallerySection(
      title: 'Library cards',
      children: [
        Wrap(
          spacing: Gap.md.w,
          runSpacing: Gap.md.h,
          children: [
            for (final item in items)
              SizedBox(
                width: width,
                height: LibraryCard.heightFor(context, width),
                child: LibraryCard(
                  item: item,
                  onPlay: noop,
                  onShare: noop,
                  onOpenFolder: noop,
                  onDelete: noop,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
