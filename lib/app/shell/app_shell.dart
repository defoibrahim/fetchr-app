import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:persistent_bottom_nav_bar_v2/persistent_bottom_nav_bar_v2.dart';

import '../../core/gen/assets.gen.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/app_icon.dart';

final _destinations = [
  (Assets.icons.home, 'Home'),
  (Assets.icons.download, 'Downloads'),
  (Assets.icons.grid, 'Library'),
  (Assets.icons.sliders, 'Settings'),
];

const _downloadsIndex = 1;

// The bar's sizes are raw design values, like the rail's theme. Style 8 fixes
// a tab at 50 dp wide and the selected one at 120, so the four fit a 320 dp
// phone; the padding makes each tab a 48 dp tap target.
const _barPadX = 12.0;
const _barPadY = 12.0;
const _tabPadX = 10.0;
const _tabPadY = 14.0;
const _tabSwitch = ItemAnimation();

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell, this.downloadsBadge});

  final StatefulNavigationShell shell;

  /// Drawn over the Downloads icon; it hides itself when there is nothing to
  /// count. The shell stays free of Riverpod and of any module.
  final Widget? downloadsBadge;

  // The icons are sized in raw design values (`AppSizes.iconNav`), so the
  // badge is placed in raw values too and keeps its place on the icon.
  static const _badgeTop = -6.0;
  static const _badgeEnd = -8.0;

  void _select(int index) =>
      shell.goBranch(index, initialLocation: index == shell.currentIndex);

  @override
  Widget build(BuildContext context) {
    if (context.windowClass.isAtLeast(WindowClass.medium)) {
      final rtl = Directionality.of(context) == TextDirection.rtl;
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: shell.currentIndex,
              onDestinationSelected: _select,
              destinations: [
                for (final (i, (icon, label)) in _destinations.indexed)
                  NavigationRailDestination(
                    icon: _icon(i, icon),
                    label: Text(label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(
              // The pages leave their bottom edge to the bar, and a rail has
              // none. The rail pads its own start side for a display cutout,
              // so the pages' SafeAreas must not pad that side again. The
              // Builder reads the MediaQuery below the Scaffold, which has
              // already removed the keyboard inset, and keeps the full
              // MediaQuery dependency off the whole shell.
              child: Builder(
                builder: (context) => MediaQuery.removePadding(
                  context: context,
                  removeLeft: !rtl,
                  removeRight: rtl,
                  child: SafeArea(
                    top: false,
                    left: false,
                    right: false,
                    child: shell,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    final tokens = context.tokens;
    final motion = ItemAnimation(
      duration: context.motion(_tabSwitch.duration),
      curve: _tabSwitch.curve,
    );
    // A re-tap on the current tab goes to its initial location, as `_select`
    // does for the rail: that is the package's default `selectedTabPressConfig`.
    return PersistentTabView.router(
      navigationShell: shell,
      backgroundColor: tokens.bg,
      navBarBuilder: (config) => Style8BottomNavBar(
        navBarConfig: config,
        navBarDecoration: NavBarDecoration(
          color: tokens.navBar,
          border: Border(top: BorderSide(color: tokens.divider)),
          padding: const EdgeInsets.symmetric(
            horizontal: _barPadX,
            vertical: _barPadY,
          ),
        ),
        itemPadding: const EdgeInsets.symmetric(
          horizontal: _tabPadX,
          vertical: _tabPadY,
        ),
        itemAnimationProperties: motion,
      ),
      tabs: [
        for (final (i, (icon, label)) in _destinations.indexed)
          PersistentRouterTabConfig(
            item: ItemConfig(
              // The selected tab shows its title, which reads the label.
              icon: Semantics(
                label: i == shell.currentIndex ? null : label,
                selected: i == shell.currentIndex,
                button: true,
                child: _EasedIconColor(motion: motion, child: _icon(i, icon)),
              ),
              title: label,
              iconSize: AppSizes.iconNav,
              activeForegroundColor: tokens.primaryIcon,
              inactiveForegroundColor: tokens.textMuted,
              activeColorSecondary: context.colors.primary,
              textStyle: context.type.navLabel.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }

  Widget _icon(int index, SvgGenImage icon) {
    final image = AppIcon(icon);
    final badge = downloadsBadge;
    if (index != _downloadsIndex || badge == null) return image;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        image,
        PositionedDirectional(top: _badgeTop, end: _badgeEnd, child: badge),
      ],
    );
  }
}

/// Style 8 swaps the icon colour at once while the pill behind it fades, so
/// the icon flashes against the old fill. This eases it over the same motion.
class _EasedIconColor extends StatelessWidget {
  const _EasedIconColor({required this.motion, required this.child});

  final ItemAnimation motion;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<Color?>(
    tween: ColorTween(end: IconTheme.of(context).color),
    duration: motion.duration,
    curve: motion.curve,
    builder: (_, color, child) => IconTheme.merge(
      data: IconThemeData(color: color),
      child: child!,
    ),
    child: child,
  );
}
