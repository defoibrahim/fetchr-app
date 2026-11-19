import Foundation

enum TaskProgress {
  static let step = 0.005

  private static let ffmpegTime = try! NSRegularExpression(pattern: #"\bout_time_(?:us|ms)=(-?\d+)"#)

  // Ticks that barely move the bar only churn every listener of the task list. Entering or leaving the unknown
  // state (-1) always passes, and so does a new ETA, stage or stall reading.
  static func changed(_ last: DownloadTask, _ next: DownloadTask) -> Bool {
    next.etaSeconds != last.etaSeconds
      || next.stage != last.stage
      || next.stalled != last.stalled
      || (next.progress < 0) != (last.progress < 0)
      || abs(next.progress - last.progress) >= step
  }

  // 0...1 from ffmpeg's -progress report: key=value blocks, newest last. out_time_us, and the older out_time_ms
  // that is microseconds too, is how much output is written; N/A before the first frame.
  static func conversion(report: String, durationSeconds: Int64) -> Double? {
    guard durationSeconds > 0 else { return nil }
    let range = NSRange(report.startIndex..., in: report)
    guard let match = ffmpegTime.matches(in: report, range: range).last,
      let group = Range(match.range(at: 1), in: report),
      let micros = Int64(report[group])
    else { return nil }
    return min(max(Double(micros) / (Double(durationSeconds) * 1e6), 0), 1)
  }
}

extension DownloadTask {
  // ffmpeg's reading while the task converts; nil when it is not converting or the bar would barely move.
  func withConversion(_ p: Double) -> DownloadTask? {
    var next = self
    next.progress = p
    guard status == .running, stage == .postProcessing, TaskProgress.changed(self, next) else { return nil }
    return next
  }
}
