import 'package:flutter/material.dart';

import '../../core/gen/assets.gen.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/theme_extensions.dart';
import '../../core/utils/scale.dart';
import '../../core/widgets/action_menu.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/segmented_pills.dart';
import '../shared/domain/entities/quality.dart';
import 'gallery_section.dart';

class ButtonsSection extends StatelessWidget {
  const ButtonsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return GallerySection(
      title: 'Buttons',
      children: [
        for (final variant in AppButtonVariant.values)
          GalleryExample(
            label: variant.name,
            child: Wrap(
              spacing: Gap.sm.w,
              runSpacing: Gap.sm.h,
              children: [
                for (final size in AppButtonSize.values)
                  AppButton(
                    label: size.name,
                    onPressed: noop,
                    variant: variant,
                    size: size,
                    expanded: false,
                  ),
              ],
            ),
          ),
        GalleryExample(
          label: 'disabled, loading, loading with a label',
          child: Wrap(
            spacing: Gap.sm.w,
            runSpacing: Gap.sm.h,
            children: [
              const AppButton(
                label: 'Disabled',
                onPressed: null,
                size: AppButtonSize.medium,
                expanded: false,
              ),
              const AppButton(
                label: 'Loading',
                onPressed: noop,
                size: AppButtonSize.medium,
                isLoading: true,
                expanded: false,
              ),
              const AppButton(
                label: 'Get formats',
                onPressed: noop,
                size: AppButtonSize.medium,
                isLoading: true,
                loadingLabel: 'Fetching…',
                expanded: false,
              ),
            ],
          ),
        ),
        GalleryExample(
          label: 'icon before, icon after, expanded',
          child: Column(
            spacing: Gap.sm.h,
            children: [
              Wrap(
                spacing: Gap.sm.w,
                runSpacing: Gap.sm.h,
                children: [
                  AppButton(
                    label: 'Paste',
                    onPressed: noop,
                    size: AppButtonSize.medium,
                    variant: AppButtonVariant.outlined,
                    icon: Assets.icons.clipboard,
                    expanded: false,
                  ),
                  AppButton(
                    label: 'Download',
                    onPressed: noop,
                    size: AppButtonSize.medium,
                    icon: Assets.icons.download,
                    iconAfter: true,
                    expanded: false,
                  ),
                ],
              ),
              const AppButton(label: 'Expanded', onPressed: noop),
            ],
          ),
        ),
      ],
    );
  }
}

class MenusSection extends StatelessWidget {
  const MenusSection({super.key});

  @override
  Widget build(BuildContext context) {
    final items = [
      ActionMenuItem.play(noop),
      ActionMenuItem.showInFolder(noop),
      ActionMenuItem.deleteFile(noop),
    ];
    return GallerySection(
      title: 'Action menu',
      children: [
        GalleryExample(
          label: 'more actions button',
          child: MoreActionsButton(items: items),
        ),
        GalleryExample(
          label: 'long press the row',
          child: ActionMenu(
            items: items,
            builder: (context, controller) => GestureDetector(
              onLongPress: controller.open,
              child: Container(
                alignment: Alignment.centerLeft,
                padding: EdgeInsets.symmetric(horizontal: Gap.lg.w),
                constraints: BoxConstraints(minHeight: AppSizes.touch.h),
                decoration: BoxDecoration(
                  color: context.tokens.surface,
                  border: Border.all(color: context.tokens.border),
                  borderRadius: BorderRadius.circular(Radii.row.r),
                ),
                child: Text('Hold me', style: context.type.body),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class PillsSection extends StatefulWidget {
  const PillsSection({super.key});

  @override
  State<PillsSection> createState() => _PillsSectionState();
}

class _PillsSectionState extends State<PillsSection> {
  Quality _quality = Quality.best;
  String _kind = 'Video';

  @override
  Widget build(BuildContext context) {
    return GallerySection(
      title: 'Segmented pills',
      children: [
        GalleryExample(
          label: 'mono, on a card',
          child: SegmentedPills<Quality>(
            items: [for (final q in Quality.values) (q, q.shortLabel)],
            selected: _quality,
            onChanged: (q) => setState(() => _quality = q),
            mono: true,
            semanticLabel: 'Default quality',
          ),
        ),
        GalleryExample(
          label: 'body, on the page',
          child: SegmentedPills<String>(
            items: const [('Video', 'Video'), ('Audio', 'Audio')],
            selected: _kind,
            onChanged: (kind) => setState(() => _kind = kind),
            trackColor: context.tokens.surface,
            semanticLabel: 'Kind',
          ),
        ),
      ],
    );
  }
}
