/// Redaction applied to every line before it reaches the log sink.
abstract final class LogFilters {
  // The backslash allowances cover JSON nested in a JSON string (a push payload).
  static final _labelledSecret = RegExp(
    r'\b(\w*?(?:token|password|passwd|secret|credential|cookie|authorization|bearer|pin|otp|ssn|ss_no|api[_-]?key|session[_-]?id))\b'
    r'''["'\\\s]*[:=]["'\\\s]*(?:(?:bearer|basic)\s+)?([^\s,;"'}\]&\\]+)''',
    caseSensitive: false,
  );

  static final _bearer = RegExp(r'\bbearer\s+\S+', caseSensitive: false);

  // Every JWT starts with eyJ (base64 of '{"'), which also keeps this linear.
  static final _jwt = RegExp(r'\beyJ[\w-]{5,}\.[\w-]{5,}\.[\w-]*');

  static final _coordinates = RegExp(
    r'-?\d{1,3}\.\d{3,}\s*,\s*-?\d{1,3}\.\d{3,}',
  );

  static final _labelledCoordinate = RegExp(
    r'''\b(lat(?:itude)?|lng|lon(?:gitude)?)\b(["'\\\s]*[:=]["'\\\s]*)-?\d+(?:\.\d+)?''',
    caseSensitive: false,
  );

  static const _mask = '***';

  /// Order matters: the labelled rule runs first because the bare `Bearer`
  /// rule would read `bearer = x` as `bearer =` and leave `x` behind.
  static String redact(String message) {
    var out = message;
    out = out.replaceAllMapped(_labelledSecret, (m) => '${m.group(1)}: $_mask');
    out = out.replaceAll(_bearer, 'Bearer $_mask');
    out = out.replaceAll(_jwt, _mask);
    out = out.replaceAll(_coordinates, '$_mask,$_mask');
    out = out.replaceAllMapped(
      _labelledCoordinate,
      (m) => '${m.group(1)}${m.group(2)}$_mask',
    );
    return out;
  }
}
