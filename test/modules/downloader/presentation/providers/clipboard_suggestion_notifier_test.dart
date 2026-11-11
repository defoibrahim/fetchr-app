import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/modules/downloader/presentation/providers/clipboard_suggestion_notifier.dart';

void main() {
  const url = 'https://youtube.com/watch?v=Qx7mT0aK3pE';
  late ProviderContainer container;

  ClipboardSuggestionNotifier notifier() =>
      container.read(clipboardSuggestionProvider.notifier);
  String? offer() => container.read(clipboardSuggestionProvider);

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  test('offers a new link from the text around it', () {
    notifier().check(clipboardText: 'look $url', fieldText: '');
    expect(offer(), url);
  });

  test("never the field's link, bare or inside text", () {
    notifier().check(clipboardText: url, fieldText: url);
    expect(offer(), isNull);
    notifier().check(clipboardText: url, fieldText: 'watch $url now');
    expect(offer(), isNull);
  });

  test('a link other than the field holds is offered', () {
    notifier().check(clipboardText: url, fieldText: 'https://example.com/b');
    expect(offer(), url);
  });

  test('never twice, even after it was taken', () {
    notifier().check(clipboardText: url, fieldText: '');
    expect(notifier().take(), url);
    expect(offer(), isNull);

    notifier().check(clipboardText: url, fieldText: '');
    expect(offer(), isNull);
  });

  test('nothing for plain text or an empty clipboard', () {
    notifier().check(clipboardText: 'hello', fieldText: '');
    notifier().check(clipboardText: null, fieldText: '');
    expect(offer(), isNull);
  });

  test('typing the offered link into the field spends it', () {
    notifier().check(clipboardText: url, fieldText: '');
    notifier().fieldChanged('https://example.com/b');
    expect(offer(), url);

    notifier().fieldChanged('see $url');
    expect(offer(), isNull);
  });

  test('take without an offer gives null', () {
    expect(notifier().take(), isNull);
  });
}
