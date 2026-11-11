const _units = ['B', 'KB', 'MB', 'GB', 'TB'];

/// One decimal below 10, none from 10. Rounding to one decimal can reach 10
/// (9.96), which then drops its decimal too.
String _number(double value) {
  final oneDecimal = value.toStringAsFixed(1);
  return double.parse(oneDecimal) >= 10 ? value.toStringAsFixed(0) : oneDecimal;
}

/// The unit index [formatBytes] picks for [bytes]. It compares the text that
/// is shown, so 1048575 moves up to MB instead of reading 1024 KB.
int _unitOf(int bytes) {
  var value = bytes.toDouble();
  var unit = 0;
  while (double.parse(_number(value)) >= 1024 && unit < _units.length - 1) {
    value /= 1024;
    unit++;
  }
  return unit;
}

double _inUnit(int bytes, int unit) {
  var value = bytes.toDouble();
  for (var i = 0; i < unit; i++) {
    value /= 1024;
  }
  return value;
}

String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  final unit = _unitOf(bytes);
  return unit == 0
      ? '$bytes B'
      : '${_number(_inUnit(bytes, unit))} ${_units[unit]}';
}

/// "118 / 184 MB": both counts in the unit of [total].
String formatBytesPair(int done, int total) {
  final unit = _unitOf(total);
  final shown = done <= 0
      ? '0'
      : unit == 0
      ? '$done'
      : _number(_inUnit(done, unit));
  return '$shown / ${formatBytes(total)}';
}

String formatSpeed(int bytesPerSecond) => '${formatBytes(bytesPerSecond)}/s';

String formatDuration(int? seconds) {
  if (seconds == null || seconds < 0) return '';
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = (seconds % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}

final _hostPrefix = RegExp(r'^(?:www|m)\.');

/// "1 video", "3 videos": [noun] takes an s for every count but one.
String plural(int n, String noun) => '$n ${n == 1 ? noun : '${noun}s'}';

/// "youtube.com · Uploader", or the site alone when there is no uploader.
String sourceLine(String url, String? uploader) {
  final who = uploader?.trim() ?? '';
  return who.isEmpty ? siteOf(url) : '${siteOf(url)} · $who';
}

/// The host of [url] without `www.` or `m.`, or [url] itself when it has none.
/// A video converted from the device is "This phone".
String siteOf(String url) {
  final parsed = Uri.tryParse(url);
  if (parsed?.scheme == 'content' || parsed?.scheme == 'file') {
    return 'This phone';
  }
  final host = parsed?.host ?? '';
  return host.isEmpty ? url : host.replaceFirst(_hostPrefix, '');
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// "Oct" for 10: English, whatever the locale, as the design's copy is.
String shortMonth(int month) => _months[month - 1];

/// "15 Oct 2026, 16:02" in local time.
String formatDateTime(DateTime date) {
  final local = date.toLocal();
  return '${local.day} ${shortMonth(local.month)} ${local.year}, '
      '${formatClock(local)}';
}

/// "09:05" from the hour and minute of [time], as given.
String formatClock(DateTime time) =>
    '${'${time.hour}'.padLeft(2, '0')}:${'${time.minute}'.padLeft(2, '0')}';
