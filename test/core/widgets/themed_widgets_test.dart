import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/theme/theme.dart';
import 'package:grabby/core/widgets/app_back_button.dart';
import 'package:grabby/core/widgets/app_text.dart';
import 'package:grabby/core/widgets/app_text_field.dart';
import 'package:grabby/core/widgets/loading_view.dart';

import 'widget_harness.dart';

TextStyle? styleOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style;

void main() {
  for (final entry in themes.entries) {
    final tokens = entry.value.extension<AppTokens>()!;

    group(entry.key, () {
      testWidgets('AppText defaults to the text token and ellipsizes', (
        tester,
      ) async {
        await tester.pumpWidget(
          themed(const AppText('hello'), theme: entry.value),
        );

        final text = tester.widget<Text>(find.text('hello'));
        expect(text.style?.color, tokens.text);
        expect(text.overflow, TextOverflow.ellipsis);
      });

      testWidgets('AppText applies size, weight and colour overrides', (
        tester,
      ) async {
        await tester.pumpWidget(
          themed(
            const AppText(
              'hello',
              size: 20,
              weight: FontWeight.w600,
              color: Colors.pink,
              maxLines: 2,
              align: TextAlign.center,
            ),
            theme: entry.value,
          ),
        );

        final text = tester.widget<Text>(find.text('hello'));
        expect(text.style?.color, Colors.pink);
        expect(text.style?.fontWeight, FontWeight.w600);
        expect(text.style?.fontSize, isNotNull);
        expect(text.maxLines, 2);
        expect(text.textAlign, TextAlign.center);
      });

      testWidgets('AppText keeps the colour of a passed style', (tester) async {
        await tester.pumpWidget(
          themed(
            const AppText('hello', style: TextStyle(color: Colors.teal)),
            theme: entry.value,
          ),
        );

        expect(styleOf(tester, 'hello')?.color, Colors.teal);
      });

      testWidgets('LoadingView shows a progress indicator', (tester) async {
        await tester.pumpWidget(
          themed(const LoadingView(), theme: entry.value),
        );

        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      });

      testWidgets('AppTextField validates and reports changes', (tester) async {
        final formKey = GlobalKey<FormState>();
        String? changed;
        await tester.pumpWidget(
          themed(
            Form(
              key: formKey,
              child: AppTextField(
                label: 'Email',
                hint: 'you@example.com',
                onChanged: (v) => changed = v,
                validator: (v) => (v ?? '').isEmpty ? 'Required' : null,
              ),
            ),
            theme: entry.value,
          ),
        );

        expect(find.text('Email'), findsOneWidget);
        expect(formKey.currentState!.validate(), isFalse);
        await tester.pump();
        expect(find.text('Required'), findsOneWidget);

        await tester.enterText(find.byType(TextFormField), 'a@b.c');
        expect(changed, 'a@b.c');
        expect(formKey.currentState!.validate(), isTrue);
      });

      testWidgets('AppTextField obscures and shows an external error', (
        tester,
      ) async {
        await tester.pumpWidget(
          themed(
            const AppTextField(obscure: true, errorText: 'Too short'),
            theme: entry.value,
          ),
        );

        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.obscureText, isTrue);
        expect(find.text('Too short'), findsOneWidget);
      });
    });
  }

  testWidgets('AppBackButton pops by default and honours onTap', (
    tester,
  ) async {
    await tester.pumpWidget(
      themed(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (_) =>
                    const Scaffold(appBar: _BackBar(), body: Text('second')),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('second'), findsOneWidget);

    await tester.tap(find.byType(AppBackButton));
    await tester.pumpAndSettle();
    expect(find.text('second'), findsNothing);

    var taps = 0;
    await tester.pumpWidget(themed(AppBackButton(onTap: () => taps++)));
    await tester.tap(find.byType(AppBackButton));
    expect(taps, 1);
  });
}

class _BackBar extends StatelessWidget implements PreferredSizeWidget {
  const _BackBar();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) =>
      AppBar(leading: const AppBackButton(), automaticallyImplyLeading: false);
}
