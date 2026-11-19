@testable import Runner

// Kotlin's TaskFixtures: a running task at 40 of 100 bytes.
enum TaskFixtures {
  static let request = DownloadRequest(
    url: "https://example.com/watch?v=abc", title: "A title", quality: .p720, folder: "Fetchr", useAria2c: false)

  static func task(
    id: String = "t1",
    request: DownloadRequest = TaskFixtures.request,
    status: TaskStatus = .running,
    progress: Double = 0.4,
    etaSeconds: Int64 = 30,
    stage: TaskStage = .downloading,
    downloadedBytes: Int64? = 40,
    totalBytes: Int64? = 100,
    speedBytesPerSec: Int64? = 5,
    stalled: Bool = false,
    errorCode: String? = nil,
    errorMessage: String? = nil,
    savedUri: String? = nil,
    savedPath: String? = nil,
    finishedAtMs: Int64? = nil,
    createdAtMs: Int64 = 1
  ) -> DownloadTask {
    DownloadTask(
      id: id, request: request, status: status, progress: progress, etaSeconds: etaSeconds, errorCode: errorCode,
      errorMessage: errorMessage, savedUri: savedUri, savedPath: savedPath, createdAtMs: createdAtMs, stage: stage,
      downloadedBytes: downloadedBytes, totalBytes: totalBytes, speedBytesPerSec: speedBytesPerSec,
      stalled: stalled, finishedAtMs: finishedAtMs)
  }
}
