import Foundation

// The task list on disk. Writes run on one serial queue, and a save requested while another is still waiting
// replaces it: only the newest list matters.
protocol TaskPersisting: AnyObject, Sendable {
  func load() -> [StoredTask]
  func save(_ tasks: [StoredTask])
}

final class TaskStore: TaskPersisting, @unchecked Sendable {
  private let url: URL
  private let queue = DispatchQueue(label: "com.defo.fetchr.task-store", qos: .utility)
  private let lock = NSLock()
  private var pending: [StoredTask]?

  init(url: URL) {
    self.url = url
  }

  // Already moved to their restart state, newest first. A missing or corrupt file is an empty list, which the next
  // save overwrites.
  func load() -> [StoredTask] {
    guard let data = try? Data(contentsOf: url) else { return [] }
    return TaskCodec.decode(data)
  }

  // Encoded on the queue, so a list replaced before its turn is never encoded.
  func save(_ tasks: [StoredTask]) {
    lock.lock()
    let writeScheduled = pending != nil
    pending = tasks
    lock.unlock()
    if !writeScheduled {
      queue.async { self.writePending() }
    }
  }

  func waitForPendingWrites() {
    queue.sync {}
  }

  private func writePending() {
    lock.lock()
    let tasks = pending
    pending = nil
    lock.unlock()
    guard let tasks else { return }
    guard let data = TaskCodec.encode(tasks) else {
      Log.downloads.error("Could not encode the download list; the stored one is kept")
      return
    }
    do {
      try data.writeAtomically(to: url)
    } catch {
      Log.downloads.error("Saving the task list failed: \(error.localizedDescription, privacy: .public)")
    }
  }
}
