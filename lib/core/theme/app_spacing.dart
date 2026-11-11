import 'dart:ui' show Size;

// Design values from the spec. Never use them raw: scale at the call site
// with .w (horizontal), .h (vertical) or .r (radii and square sizes).
abstract final class Gap {
  static const xs = 4.0, sm = 8.0, md = 12.0, lg = 16.0, xl = 24.0;
  static const gutter = 20.0, gutterNarrow = 16.0; // narrow: Breakpoints.narrow
}

// Logical dp from the spec, used raw and never through .w/.h: a window class
// or a width cap that stretched with the screen would not be a cap.
abstract final class Breakpoints {
  /// Below this width the gutter, hero and pills tighten and error actions
  /// stack.
  static const narrow = 360.0;

  /// From here the shell uses a rail, the Library has 3 columns and the format
  /// picker is a dialog. Scaling stops here too (`ScaleScope`).
  static const medium = 600.0;

  /// From here the Library has 4 columns and the Player splits in two.
  static const expanded = 840.0;

  /// Under this window height the format picker stays a bottom sheet, which is
  /// a landscape phone even when it is wider than [medium].
  static const compactHeight = 480.0;

  /// The widest a page's content runs (`CenteredContent`).
  static const contentMax = 560.0;

  /// The width of the format picker dialog.
  static const dialogWidth = 480.0;
}

enum WindowClass {
  narrow,
  compact,
  medium,
  expanded;

  /// The class of a window [width] in logical dp.
  static WindowClass of(double width) => switch (width) {
    < Breakpoints.narrow => narrow,
    < Breakpoints.medium => compact,
    < Breakpoints.expanded => medium,
    _ => expanded,
  };

  /// `windowClass.isAtLeast(WindowClass.medium)` is the rail, dialog and
  /// multi-column test.
  bool isAtLeast(WindowClass other) => index >= other.index;
}

abstract final class Radii {
  static const pill = 999.0,
      sheet = 28.0,
      notif = 24.0,
      card = 18.0,
      control = 16.0,
      row = 14.0,
      button = 12.0,
      thumb = 10.0,
      thumbSmall = 8.0,
      logo = 9.0,
      pillInner = 9.0;
}

abstract final class AppSizes {
  static const input = 56.0,
      buttonLarge = 54.0,
      buttonMedium = 48.0,
      buttonCompact = 46.0,
      buttonSmall = 44.0,
      touch = 44.0,
      rowRecent = 64.0,
      rowPlaylist = 62.0,
      rowOption = 50.0,
      iconNav = 20.0,
      iconButton = 18.0,
      iconBack = 22.0,
      iconStatus = 20.0,
      logoTile = 30.0,
      logoGlyph = 18.0,
      errorIconTile = 40.0,
      dialogIconTile = 44.0;
  static const navIndicator = Size(56, 30);
}
