import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/app/gallery/gallery_view.dart';
import 'package:grabby/app/theme/accent_provider.dart';
import 'package:grabby/core/theme/theme.dart';
import 'package:grabby/core/widgets/app_button.dart';
import 'package:grabby/core/widgets/app_progress_bar.dart';
import 'package:grabby/core/widgets/error_card.dart';
import 'package:grabby/core/widgets/media_thumb.dart';
import 'package:grabby/core/widgets/segmented_pills.dart';
import 'package:grabby/core/widgets/sheet_drag_handle.dart';
import 'package:grabby/modules/downloader/presentation/views/widgets/attention_row.dart';
import 'package:grabby/modules/downloader/presentation/views/widgets/download_card.dart';
import 'package:grabby/modules/downloader/presentation/views/widgets/quality_option.dart';
import 'package:grabby/modules/downloader/presentation/views/widgets/url_field.dart';
import 'package:grabby/modules/library/presentation/views/widgets/library_card.dart';

import '../../core/widgets/widget_harness.dart';
import '../../support/mocks.dart';

Future<void> _pump(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  List<Override> overrides = const [],
}) => pumpThemed(
  tester,
  ProviderScope(overrides: overrides, child: const GalleryView()),
  size: size,
);

final _lightSwitch = find.descendant(
  of: find.byType(AppBar),
  matching: find.byType(Switch),
);

Brightness _brightness(WidgetTester tester) =>
    Theme.of(tester.element(find.text('BUTTONS'))).brightness;

Future<void> _tapButton(WidgetTester tester, String label) async {
  final button = find.widgetWithText(AppButton, label);
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('shows every section', (tester) async {
    await _pump(tester);

    for (final title in [
      'BUTTONS',
      'MEDIA THUMBNAILS',
      'ERROR CARDS',
      'ACTION MENU',
      'SEGMENTED PILLS',
      'PROGRESS BAR',
      'EMPTY VIEW',
      'DIALOG, SHEET AND SNACKBARS',
      'CONTROLS',
      'URL FIELD',
      'QUALITY OPTIONS',
      'FETCH ERRORS',
      'DOWNLOAD CARDS',
      'FAILED DOWNLOADS',
      'LIBRARY CARDS',
    ]) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
  });

  testWidgets('shows each component in more than one state', (tester) async {
    await _pump(tester);

    expect(
      find.byType(AppButton),
      findsAtLeastNWidgets(
        AppButtonVariant.values.length * AppButtonSize.values.length,
      ),
    );
    expect(find.byType(MediaThumb), findsAtLeastNWidgets(5));
    // Three core examples, seven fetch errors, eight failed downloads.
    expect(find.byType(ErrorCard), findsNWidgets(18));
    expect(find.byType(UrlField), findsNWidgets(UrlFieldState.values.length));
    expect(find.byType(QualityOption), findsNWidgets(2));
    expect(find.byType(DownloadCard), findsNWidgets(8));
    expect(find.byType(AttentionRow), findsNWidgets(8));
    expect(find.byType(LibraryCard), findsNWidgets(2));
    expect(find.byType(AppProgressBar), findsAtLeastNWidgets(5));
  });

  testWidgets('opens dark and the app bar switch makes it light', (
    tester,
  ) async {
    await _pump(tester);
    expect(_brightness(tester), Brightness.dark);

    await tester.tap(_lightSwitch);
    await tester.pump();
    expect(_brightness(tester), Brightness.light);

    await tester.tap(_lightSwitch);
    await tester.pump();
    expect(_brightness(tester), Brightness.dark);
  });

  testWidgets('follows the chosen accent', (tester) async {
    await _pump(
      tester,
      overrides: [
        accentProvider.overrideWith(
          () => FixedAccent(AppPalette.accents[2].color),
        ),
      ],
    );

    expect(
      Theme.of(
        tester.element(find.text('BUTTONS')),
      ).extension<AppTokens>()!.accent,
      AppPalette.accents[2].color,
    );
  });

  testWidgets('the confirm dialog opens and Cancel closes it', (tester) async {
    await _pump(tester);

    await _tapButton(tester, 'Confirm dialog');
    expect(find.text('Delete this file?'), findsOneWidget);
    expect(find.text('Movies/Fetchr'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('the bottom sheet opens', (tester) async {
    await _pump(tester);

    await _tapButton(tester, 'Bottom sheet');

    expect(find.text('Sheet title'), findsOneWidget);
    expect(find.byType(SheetDragHandle), findsOneWidget);
  });

  testWidgets('each snackbar button shows its message', (tester) async {
    await _pump(tester);

    for (final (button, message) in [
      ('Info snackbar', 'Link copied'),
      ('Success snackbar', 'Saved to Movies/Fetchr'),
      ('Error snackbar', 'Could not save the file'),
      ('Snackbar with an action', 'Download paused'),
      ('Undo snackbar', 'File deleted'),
    ]) {
      await _tapButton(tester, button);
      expect(find.text(message), findsOneWidget, reason: button);
    }
  });

  testWidgets('a pill tap moves the selection', (tester) async {
    await _pump(tester);

    await tester.ensureVisible(find.text('Audio'));
    await tester.tap(find.text('Audio'));
    await tester.pump();

    final pills = tester.widget<SegmentedPills<String>>(
      find.byType(SegmentedPills<String>),
    );
    expect(pills.selected, 'Audio');
  });

  for (final brightness in Brightness.values) {
    for (final size in [const Size(320, 640), const Size(390, 844)]) {
      testWidgets('lays out without overflow: ${brightness.name} at $size', (
        tester,
      ) async {
        await _pump(tester, size: size);
        if (brightness == Brightness.light) {
          await tester.tap(_lightSwitch);
          await tester.pump();
        }

        expect(tester.takeException(), isNull);
      });
    }
  }
}
