enum YtDlpSchedule {
  private static let intervalMs: Int64 = 24 * 60 * 60 * 1000

  // Due when enabled and 24 h have passed since the last check, or the clock moved back.
  static func isDue(lastCheckedMs: Int64, nowMs: Int64, enabled: Bool) -> Bool {
    guard enabled else { return false }
    let elapsed = nowMs - lastCheckedMs
    return elapsed < 0 || elapsed >= intervalMs
  }
}
