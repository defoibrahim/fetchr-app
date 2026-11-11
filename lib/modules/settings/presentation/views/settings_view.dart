import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/shared/domain/entities/quality.dart';
import '../../../../app/shared/download_prefs_provider.dart';
import '../../../../app/theme/accent_provider.dart';
import '../../../../app/theme/theme_mode_provider.dart';
import '../../../../core/gen/assets.gen.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/theme_extensions.dart';
import '../../../../core/utils/scale.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/centered_content.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/segmented_pills.dart';
import 'widgets/accent_swatches.dart';
import 'widgets/folder_dialog.dart';
import 'widgets/settings_section.dart';
import 'widgets/yt_dlp_card.dart';

const _titleTop = 28.0;
const _titleBottom = 8.0;
const _sectionGap = 22.0;
const _rowIcon = 20.0;
const _chevron = 18.0;
const _textGap = 3.0;

// A cover photo is a per-video pick, not a default.
final _qualities = [
  for (final quality in Quality.values)
    if (quality != Quality.cover) (quality, quality.shortLabel),
];

const _themes = [
  (ThemeMode.system, 'System'),
  (ThemeMode.dark, 'Dark'),
  (ThemeMode.light, 'Light'),
];

class SettingsView extends ConsumerWidget {
  const SettingsView({super.key});

  Future<void> _editFolder(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final name = await showFolderDialog(context, current);
    if (!context.mounted || name == null || name == current) return;
    await ref.read(downloadPrefsProvider.notifier).setFolder(name);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(downloadPrefsProvider);
    final prefsNotifier = ref.read(downloadPrefsProvider.notifier);
    final gutter = context.gutter;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CenteredContent(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(gutter, 0, gutter, Gap.xl.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: _sectionGap.h,
              children: [
                Padding(
                  padding: EdgeInsets.only(
                    top: _titleTop.h,
                    bottom: _titleBottom.h,
                  ),
                  child: const ScreenTitle('Settings'),
                ),
                SettingsSection(
                  title: 'Downloads',
                  rows: [
                    SettingsField(
                      title: 'Default quality',
                      child: SegmentedPills<Quality>(
                        items: _qualities,
                        selected: prefs.quality,
                        mono: true,
                        semanticLabel: 'Default quality',
                        onChanged: (quality) =>
                            unawaited(prefsNotifier.setQuality(quality)),
                      ),
                    ),
                    _FolderRow(
                      folder: prefs.folder,
                      onTap: () => _editFolder(context, ref, prefs.folder),
                    ),
                    SettingsSwitchRow(
                      title: 'Faster downloads (aria2c)',
                      subtitle: 'Splits large files into parallel parts',
                      value: prefs.useAria2c,
                      onChanged: (enabled) =>
                          unawaited(prefsNotifier.setUseAria2c(enabled)),
                    ),
                  ],
                ),
                SettingsSection(
                  title: 'Appearance',
                  rows: [
                    SettingsField(
                      title: 'Theme',
                      child: SegmentedPills<ThemeMode>(
                        items: _themes,
                        selected: ref.watch(themeModeProvider),
                        semanticLabel: 'Theme',
                        onChanged: (mode) => unawaited(
                          ref.read(themeModeProvider.notifier).setMode(mode),
                        ),
                      ),
                    ),
                    SettingsField(
                      title: 'Accent',
                      child: AccentSwatches(
                        selected: ref.watch(accentProvider),
                        onSelected: (accent) => unawaited(
                          ref.read(accentProvider.notifier).setAccent(accent),
                        ),
                      ),
                    ),
                  ],
                ),
                const YtDlpCard(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FolderRow extends StatelessWidget {
  const _FolderRow({required this.folder, required this.onTap});

  final String folder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final type = context.type;
    return MergeSemantics(
      child: Semantics(
        button: true,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: AppSizes.buttonMedium.h),
            child: Row(
              spacing: Gap.md.w,
              children: [
                AppIcon(
                  Assets.icons.folder,
                  size: _rowIcon.r,
                  color: tokens.textMuted,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: _textGap.h,
                    children: [
                      Text('Save folder', style: type.bodyStrong),
                      Text(
                        '${Quality.best.savePath(folder)} · '
                        '${Quality.mp3.savePath(folder)}',
                        // A path reads left to right in any language.
                        textDirection: TextDirection.ltr,
                        style: type.mono.copyWith(color: tokens.textMuted),
                      ),
                    ],
                  ),
                ),
                AppIcon(
                  Assets.icons.chevronRight,
                  size: _chevron.r,
                  color: tokens.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
