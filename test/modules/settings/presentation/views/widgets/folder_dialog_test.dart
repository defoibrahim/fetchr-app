import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/widgets/app_button.dart';
import 'package:grabby/modules/settings/presentation/views/widgets/folder_dialog.dart';

import '../../../../../core/widgets/widget_harness.dart';

void main() {
  group('validateFolderName', () {
    test('rejects null, empty and blank', () {
      expect(validateFolderName(null), isNotNull);
      expect(validateFolderName(''), isNotNull);
      expect(validateFolderName('   '), isNotNull);
    });

    for (final char in r'/\:*?"<>|'.split('')) {
      test('rejects $char', () {
        expect(validateFolderName('a${char}b'), isNotNull);
      });
    }

    test('rejects a leading dot, which safeFolder would strip', () {
      expect(validateFolderName('.x'), isNotNull);
      expect(validateFolderName('..hidden'), isNotNull);
      expect(validateFolderName('  .x'), isNotNull);
    });

    test('says why a leading dot fails', () {
      expect(validateFolderName('.x'), "A name can't start with a dot");
    });

    test('accepts a plain name, spaces and dots inside', () {
      expect(validateFolderName('Fetchr'), isNull);
      expect(validateFolderName('My videos 2.0'), isNull);
      expect(validateFolderName('a.b'), isNull);
      expect(validateFolderName('  padded  '), isNull);
    });
  });

  group('showFolderDialog', () {
    String? result;
    var closed = false;

    Future<void> open(WidgetTester tester, String current) async {
      result = null;
      closed = false;
      await tester.pumpWidget(
        themed(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showFolderDialog(context, current);
                closed = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('starts with the current name', (tester) async {
      await open(tester, 'Fetchr');

      final field = tester.widget<TextFormField>(find.byType(TextFormField));
      expect(field.controller?.text, 'Fetchr');
    });

    testWidgets('Save returns the trimmed name', (tester) async {
      await open(tester, 'Fetchr');

      await tester.enterText(find.byType(TextFormField), '  Clips  ');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(closed, isTrue);
      expect(result, 'Clips');
    });

    testWidgets('an invalid name shows the error and keeps the dialog', (
      tester,
    ) async {
      await open(tester, 'Fetchr');

      await tester.enterText(find.byType(TextFormField), 'a/b');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(closed, isFalse);
      expect(find.textContaining('Use no'), findsOneWidget);
    });

    testWidgets('an empty name shows the error and keeps the dialog', (
      tester,
    ) async {
      await open(tester, 'Fetchr');

      await tester.enterText(find.byType(TextFormField), '');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(closed, isFalse);
      expect(find.text('Enter a folder name'), findsOneWidget);
    });

    testWidgets('Cancel returns null', (tester) async {
      await open(tester, 'Fetchr');

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(closed, isTrue);
      expect(result, isNull);
    });

    testWidgets('a leading dot shows its own message and keeps the dialog', (
      tester,
    ) async {
      await open(tester, 'Fetchr');

      await tester.enterText(find.byType(TextFormField), '.x');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(closed, isFalse);
      expect(find.text("A name can't start with a dot"), findsOneWidget);
    });

    testWidgets('a blank name shows the error and keeps the dialog', (
      tester,
    ) async {
      await open(tester, 'Fetchr');

      await tester.enterText(find.byType(TextFormField), '   ');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(closed, isFalse);
      expect(find.text('Enter a folder name'), findsOneWidget);
    });

    testWidgets('lays out a title, the field and two themed buttons', (
      tester,
    ) async {
      await open(tester, 'Fetchr');

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Save folder'), findsOneWidget);
      final cancel = tester.widget<AppButton>(
        find.widgetWithText(AppButton, 'Cancel'),
      );
      final save = tester.widget<AppButton>(
        find.widgetWithText(AppButton, 'Save'),
      );
      expect(cancel.variant, AppButtonVariant.outlined);
      expect(save.variant, AppButtonVariant.filled);
    });

    testWidgets('scrolls instead of overflowing on a short screen', (
      tester,
    ) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(320, 220);
      addTearDown(tester.view.reset);
      await open(tester, 'Fetchr');

      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Save').hitTestable(), findsOneWidget);
    });
  });
}
