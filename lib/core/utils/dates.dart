/// [ms] since the epoch as a [DateTime], or null when [ms] is null.
DateTime? dateFromMs(int? ms) =>
    ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);

/// Local midnight of the day [time] falls on. Comparing these, not 24 h spans,
/// survives a daylight-saving change.
DateTime localDay(DateTime time) {
  final local = time.toLocal();
  return DateTime(local.year, local.month, local.day);
}
