import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/routes/app_routes.dart';
import '../../../../../core/gen/assets.gen.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/theme_extensions.dart';
import '../../../../../core/utils/formatters.dart';
import '../../../../../core/utils/scale.dart';
import '../../../../../core/widgets/empty_view.dart';
import '../../../domain/entities/download_task.dart';
import '../../../domain/extensions/download_task_extensions.dart';
import '../../formatters/download_task_formatter.dart';
import '../../providers/downloads_notifier.dart';
import 'media_row.dart';

const _maxShown = 3;
const _topGap = 26.0;
const _rowGap = 4.0;

/// A sliver: the three newest finished downloads under "Recent", or the empty
/// state centred in the space that is left. [gutter] is the scaled side
/// padding of the page.
class HomeRecent extends ConsumerWidget {
  const HomeRecent({super.key, required this.gutter});

  final double gutter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(downloadsNotifierProvider).value;
    // The Downloads tab owns loading and error states; Home just stays quiet.
    if (tasks == null) return const SliverToBoxAdapter();
    final recent = tasks.recentlySaved(_maxShown);
    if (recent.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: EmptyView(
          illustration: Assets.icons.emptyHome,
          message: 'Your downloads will show up here.',
        ),
      );
    }
    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: gutter),
      sliver: SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: _topGap.h),
            _header(context),
            SizedBox(height: Gap.sm.h),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: _rowGap.h,
              children: [
                for (final task in recent)
                  MediaRow(
                    title: task.request.title,
                    meta: task.recentMeta,
                    thumbnailUrl: task.request.thumbnail,
                    duration: formatDuration(task.request.durationSec),
                    isAudio: task.request.quality.isAudio,
                    onTap: () => _play(context, task),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text('Recent', style: context.type.section)),
        TextButton(
          onPressed: () => context.go(AppRoutes.library),
          style: TextButton.styleFrom(
            foregroundColor: context.tokens.textMuted,
            minimumSize: Size(0, AppSizes.touch.h),
            padding: EdgeInsets.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: context.type.body,
          ),
          child: const Text('See library'),
        ),
      ],
    );
  }

  void _play(BuildContext context, DownloadTask task) {
    unawaited(
      context.push(
        AppRoutes.playerLocation(
          uri: task.savedUri!,
          title: task.request.title,
        ),
      ),
    );
  }
}
