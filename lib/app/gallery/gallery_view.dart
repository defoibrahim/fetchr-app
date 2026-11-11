import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/scale.dart';
import '../theme/accent_provider.dart';
import 'gallery_actions.dart';
import 'gallery_controls.dart';
import 'gallery_feedback.dart';
import 'gallery_media.dart';
import 'gallery_modules.dart';

/// Every core and module component in every state, for checking a device by
/// eye. It opens
/// dark whatever the app's mode is; the switch in the app bar flips it light.
/// Only debug builds route here.
class GalleryView extends ConsumerStatefulWidget {
  const GalleryView({super.key});

  @override
  ConsumerState<GalleryView> createState() => _GalleryViewState();
}

class _GalleryViewState extends ConsumerState<GalleryView> {
  var _light = false;

  @override
  Widget build(BuildContext context) {
    final accent = ref.watch(accentProvider);
    return Theme(
      data: _light ? AppTheme.light(accent) : AppTheme.dark(accent),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Gallery'),
          actions: [
            const Text('Light'),
            Semantics(
              label: 'Light theme',
              child: Switch(
                value: _light,
                onChanged: (value) => setState(() => _light = value),
              ),
            ),
            SizedBox(width: Gap.sm.w),
          ],
        ),
        // Eager, so every section exists whatever is on screen.
        body: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            Gap.gutter.w,
            Gap.lg.h,
            Gap.gutter.w,
            Gap.xl.h,
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ButtonsSection(),
              ThumbsSection(),
              ErrorCardsSection(),
              MenusSection(),
              PillsSection(),
              ProgressSection(),
              EmptySection(),
              OverlaysSection(),
              ControlsSection(),
              UrlFieldSection(),
              QualityOptionsSection(),
              FetchErrorsSection(),
              DownloadCardsSection(),
              AttentionRowsSection(),
              LibraryCardsSection(),
            ],
          ),
        ),
      ),
    );
  }
}
