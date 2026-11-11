import 'package:flutter/material.dart';

import '../gen/assets.gen.dart';
import '../theme/app_spacing.dart';
import '../theme/theme_extensions.dart';
import '../utils/scale.dart';
import 'app_icon.dart';
import 'app_icon_button.dart';

class ActionMenuItem {
  const ActionMenuItem({
    required this.icon,
    required this.label,
    required this.onSelected,
    this.destructive = false,
  });

  // The file actions every list of saved files offers, worded once.
  ActionMenuItem.play(VoidCallback onSelected)
    : this(icon: Assets.icons.play, label: 'Play', onSelected: onSelected);

  ActionMenuItem.share(VoidCallback onSelected)
    : this(icon: Assets.icons.share, label: 'Share', onSelected: onSelected);

  ActionMenuItem.showInFolder(VoidCallback onSelected)
    : this(
        icon: Assets.icons.folder,
        label: 'Show in folder',
        onSelected: onSelected,
      );

  ActionMenuItem.deleteFile(VoidCallback onSelected)
    : this(
        icon: Assets.icons.trash,
        label: 'Delete file',
        onSelected: onSelected,
        destructive: true,
      );

  final SvgGenImage icon;
  final String label;
  final VoidCallback onSelected;
  final bool destructive;
}

/// A popup of icon + label rows. The panel and the rows take their colours,
/// shape and shadow from `menuTheme` and `menuButtonTheme`; this adds the
/// width and the placement. `builder` gets the controller, so an anchor can
/// open the menu on tap or on a long press.
class ActionMenu extends StatelessWidget {
  const ActionMenu({super.key, required this.items, required this.builder});

  static const width = 176.0;

  final List<ActionMenuItem> items;
  final Widget Function(BuildContext context, MenuController controller)
  builder;

  @override
  Widget build(BuildContext context) {
    final menuWidth = width.w;
    final error = context.tokens.error;
    return MenuAnchor(
      style: MenuStyle(
        fixedSize: WidgetStatePropertyAll(Size.fromWidth(menuWidth)),
        // Below the anchor, with the two end edges flush: the menu extends
        // back over the anchor, which usually sits at the end of a row.
        alignment: AlignmentDirectional.bottomEnd,
      ),
      alignmentOffset: Offset(-menuWidth, Gap.xs.h),
      // Unconstrained, the panel is as wide as its widest row and ignores
      // the fixed width above.
      crossAxisUnconstrained: false,
      builder: (context, controller, _) => builder(context, controller),
      menuChildren: [
        for (final item in items)
          MenuItemButton(
            onPressed: item.onSelected,
            leadingIcon: AppIcon(item.icon),
            style: item.destructive
                ? MenuItemButton.styleFrom(
                    foregroundColor: error,
                    iconColor: error,
                  )
                : null,
            child: Text(item.label),
          ),
      ],
    );
  }
}

/// The three-dot button that opens an [ActionMenu].
class MoreActionsButton extends StatelessWidget {
  const MoreActionsButton({super.key, required this.items});

  final List<ActionMenuItem> items;

  @override
  Widget build(BuildContext context) => ActionMenu(
    items: items,
    builder: (_, controller) => MoreActionsDots(controller: controller),
  );
}

/// The dots alone, for an anchor that also opens [controller] another way
/// (the Library card's long press).
class MoreActionsDots extends StatelessWidget {
  const MoreActionsDots({super.key, required this.controller});

  final MenuController controller;

  @override
  Widget build(BuildContext context) => AppIconButton(
    icon: Assets.icons.moreVertical,
    tooltip: 'More actions',
    onPressed: () => controller.isOpen ? controller.close() : controller.open(),
  );
}
