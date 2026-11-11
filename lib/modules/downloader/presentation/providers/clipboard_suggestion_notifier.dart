import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/extensions/string_extensions.dart';

/// The clipboard link Home offers under the field, or null.
class ClipboardSuggestionNotifier extends Notifier<String?> {
  // Every link offered so far, so one is offered once however often the app
  // resumes.
  Set<String> _offered = const {};

  @override
  String? build() => null;

  /// Offers the clipboard's link, never the one the field already holds and
  /// never one offered before.
  void check({required String? clipboardText, required String fieldText}) {
    final url = clipboardText.firstUrl;
    if (url == null || _offered.contains(url) || url == fieldText.firstUrl) {
      return;
    }
    _offered = {..._offered, url};
    state = url;
  }

  /// The field now holding the offered link spends the offer.
  void fieldChanged(String text) {
    if (state != null && text.firstUrl == state) state = null;
  }

  /// The offered link, which is then spent.
  String? take() {
    final url = state;
    state = null;
    return url;
  }
}

// Not autoDispose: the offered set has to outlive a paused Home tab.
final clipboardSuggestionProvider =
    NotifierProvider<ClipboardSuggestionNotifier, String?>(
      ClipboardSuggestionNotifier.new,
    );
