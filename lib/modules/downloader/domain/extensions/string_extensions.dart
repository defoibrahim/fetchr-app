final _url = RegExp(r'\bhttps?://[^\s<>"]+', caseSensitive: false);

const _trailing = '.,;:!?\'")]}';

extension LinkText on String? {
  /// The first http(s) link in pasted or shared text, or null.
  String? get firstUrl {
    final text = this;
    if (text == null) return null;
    for (final match in _url.allMatches(text)) {
      final url = _trimTrailing(match[0]!);
      if (Uri.tryParse(url)?.host.isNotEmpty ?? false) return url;
    }
    return null;
  }
}

// Share text wraps links in prose and brackets; a `)` that closes a `(` inside
// the URL (Wikipedia titles) belongs to it.
String _trimTrailing(String url) {
  var end = url.length;
  while (end > 0 && _trailing.contains(url[end - 1])) {
    if (url[end - 1] == ')' && _balanced(url.substring(0, end))) break;
    end--;
  }
  return url.substring(0, end);
}

bool _balanced(String s) =>
    '('.allMatches(s).length >= ')'.allMatches(s).length;
