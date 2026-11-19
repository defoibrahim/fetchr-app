enum TempDirs {
  // Dir names under Library/Caches/tasks that no paused or failed task owns.
  static func orphans(_ dirNames: [String], tasks: [DownloadTask]) -> [String] {
    let kept = Set(tasks.filter { TaskTransitions.keepsPartialFiles($0.status) }.map(\.id))
    return dirNames.filter { !kept.contains($0) }
  }
}
