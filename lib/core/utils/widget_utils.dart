import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/theme_extensions.dart';
import '../widgets/sheet_drag_handle.dart';
import 'scale.dart';

const _heightFraction = 0.88;
const _landscapeHeightFraction = 0.9;
const _grabberTop = 10.0;
const _grabberBottom = 4.0;
// The grabber's own height, which the dialog does not draw.
const _grabberHeight = 4.0;
const _enter = Duration(milliseconds: 300);
const _exit = Duration(milliseconds: 250);
const _fade = Duration(milliseconds: 150);

/// A bottom sheet on a phone, a [Breakpoints.dialogWidth] dialog from
/// [Breakpoints.medium] wide, except in a window shorter than
/// [Breakpoints.compactHeight] (a landscape phone), which keeps the sheet.
/// Colour, shape and barrier come from `BottomSheetThemeData` and
/// `DialogThemeData`.
Future<T?> showAppBottomSheet<T>(
  BuildContext context, {
  required Widget child,
}) {
  final size = MediaQuery.sizeOf(context);
  final dialog =
      size.width >= Breakpoints.medium &&
      size.height >= Breakpoints.compactHeight;
  return dialog
      ? _showDialog<T>(context, child)
      : _showSheet<T>(context, child);
}

// A tab's own navigator ends above the bottom bar, which would stay visible
// and tappable under either, so both go to the root navigator.
Future<T?> _showSheet<T>(BuildContext context, Widget child) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    useRootNavigator: true,
    sheetAnimationStyle: AnimationStyle(
      duration: context.motion(_enter),
      reverseDuration: context.motion(_exit),
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    ),
    builder: (sheetContext) {
      final media = MediaQuery.of(sheetContext);
      final landscape = media.orientation == Orientation.landscape;
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight:
              media.size.height *
              (landscape ? _landscapeHeightFraction : _heightFraction),
        ),
        child: Padding(
          // A scroll-controlled sheet does not make room for the keyboard
          // itself.
          padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: EdgeInsets.only(
                    top: _grabberTop.h,
                    bottom: _grabberBottom.h,
                  ),
                  child: const SheetDragHandle(),
                ),
                Flexible(child: child),
              ],
            ),
          ),
        ),
      );
    },
  );
}

Future<T?> _showDialog<T>(BuildContext context, Widget child) {
  return showDialog<T>(
    context: context,
    useRootNavigator: true,
    animationStyle: AnimationStyle(
      duration: context.motion(_fade),
      reverseDuration: context.motion(_fade),
    ),
    builder: (dialogContext) => Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: Breakpoints.dialogWidth,
          maxWidth: Breakpoints.dialogWidth,
          maxHeight: MediaQuery.sizeOf(dialogContext).height * _heightFraction,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The body is laid out for a sheet with a grabber above it.
            SizedBox(height: (_grabberTop + _grabberHeight + _grabberBottom).h),
            Flexible(child: child),
          ],
        ),
      ),
    ),
  );
}
