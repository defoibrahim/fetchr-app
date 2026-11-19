import Foundation

final class DownloadsStream: DownloadsStreamHandler {
  private static let interval: UInt64 = 250_000_000
  private let repository: DownloadRepository
  // Touched only on the main thread, where Flutter calls onListen and onCancel.
  private var forwarding: Task<Void, Never>?

  init(repository: DownloadRepository) {
    self.repository = repository
  }

  override func onListen(withArguments arguments: Any?, sink: PigeonEventSink<DownloadsSnapshot>) {
    forwarding?.cancel()
    forwarding = Task { [repository] in
      // The stream keeps only the newest list, so sleeping after a send conflates what changed meanwhile into
      // the next one: at most one snapshot per 250 ms, and the last one always arrives.
      for await tasks in await repository.snapshots {
        await MainActor.run {
          guard !Task.isCancelled else { return }
          sink.success(DownloadsSnapshot(tasks: tasks))
        }
        try? await Task.sleep(nanoseconds: Self.interval)
      }
    }
  }

  override func onCancel(withArguments arguments: Any?) {
    forwarding?.cancel()
    forwarding = nil
  }
}
