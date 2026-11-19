import Foundation

extension DownloadRepository {
  // One attempt, from its turn to its end. An attempt that no longer owns its task (paused, canceled, removed,
  // superseded) has already given its slot up, and its reply changes nothing.
  func execute(_ key: String, _ req: DownloadRequest) async {
    let id = Self.taskId(of: key)
    if owns(key) {
      await attempt(key, id, req)
    }
    release(key)
    if !keepsDir(id) {
      await removeDir(id)
    }
  }

  private func attempt(_ key: String, _ id: String, _ req: DownloadRequest) async {
    let dir = taskDir(id)
    do {
      // Not wiped: yt-dlp continues the .part files an earlier attempt left here.
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      if req.quality == .mp3 { Self.discardCutShortConversion(in: dir) }
      let argv: [String]
      let url: String
      // Staged after the cleanup above, which would take a staged .mp3 for a cut-short conversion.
      if LocalVideo.isLocal(req.url) {
        let staged = try await stage(req, in: dir)
        guard owns(key) else { return }
        argv = RequestBuilder.convertArgv(source: staged, cacheDir: cachesDir)
        url = RequestBuilder.convertUrl(source: staged)
      } else {
        argv = RequestBuilder.downloadArgv(req, outDir: dir, cacheDir: cachesDir)
        url = req.url
      }
      // A run that starts while yt-dlp is being updated waits here, and may have been paused or canceled meanwhile.
      await gate.enter()
      guard owns(key) else {
        await gate.leave()
        return
      }
      // The stall clock starts here, after any earlier attempt has unwound, not while the attempt waited its turn.
      inPython[key] = now()
      let conversion = watchConversion(key, req, dir)
      defer {
        inPython[key] = nil
        conversion?.cancel()
      }
      // Left only once Python returns: an abandoned call still unwinding is still running yt-dlp.
      let payload: [String: Any] = ["argv": argv, "url": url, "task": key, "outDir": dir.path]
      var failure: Error?
      do { _ = try await python.call("download", payload) } catch { failure = error }
      await gate.leave()
      if let failure { throw failure }
      guard owns(key) else { return }
      let file = try SaveLocation.pickResult(in: dir, quality: req.quality)
      let bytes = Int64((try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
      let folder = SaveLocation.relativeFolder(req)
      let saved = try SaveLocation.save(file, toRelativeFolder: folder, documents: documents)
      savedFiles[id] = "\(folder)/\(saved.lastPathComponent)"
      let finishedAt = now().epochMs
      let done = settle(id) {
        TaskTransitions.complete($0, savedPath: folder, bytes: bytes, nowMs: finishedAt).map(withUri)
      }
      if done {
        discardPicked(req)
      }
    } catch {
      guard owns(key) else { return }
      let (code, message) = ErrorClassifier.classify(error)
      Log.downloads.error("Task \(id, privacy: .public) failed: \(code, privacy: .public)")
      let failedAt = now().epochMs
      settle(id) { TaskTransitions.fail($0, code: code, message: message, finishedAtMs: failedAt) }
    }
  }

  // Off the actor: a copy of a long video can take a while where the volume cannot clone it.
  private func stage(_ req: DownloadRequest, in dir: URL) async throws -> URL {
    guard let source = LocalVideo.resolve(req.url, documents: documents, picked: pickedDir) else {
      throw LocalVideo.gone
    }
    var local = req
    local.url = source.file.absoluteString
    return try await Task.detached(priority: .userInitiated) { try LocalVideo.stage(local, into: dir) }.value
  }

  // ffmpeg writes the MP3 under its final name, so a conversion stopped by a pause or a kill leaves a partial x.mp3
  // that yt-dlp would take as already downloaded and the run would save truncated. Partial downloads are .part files
  // and stay; the conversion and its report start again.
  private static func discardCutShortConversion(in dir: URL) {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
    for name in names where name.lowercased().hasSuffix(".mp3") || name == RequestBuilder.conversionReport {
      try? FileManager.default.removeItem(at: dir.appendingPathComponent(name, isDirectory: false))
    }
  }

  // yt-dlp says nothing while ffmpeg converts to MP3; ffmpeg's -progress report says how far it has got.
  private func watchConversion(_ key: String, _ req: DownloadRequest, _ dir: URL) -> Task<Void, Never>? {
    guard req.quality == .mp3, let seconds = req.durationSeconds, seconds > 0 else { return nil }
    let report = dir.appendingPathComponent(RequestBuilder.conversionReport, isDirectory: false)
    let interval = UInt64(conversionPoll * 1e9)
    return Task.detached(priority: .utility) { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: interval)
        guard let self, await self.converting(key),
          let text = try? String(contentsOf: report, encoding: .utf8),
          let progress = TaskProgress.conversion(report: text, durationSeconds: seconds)
        else { continue }
        await self.applyConversion(key, progress)
      }
    }
  }

  private func converting(_ key: String) -> Bool {
    owns(key) && task(Self.taskId(of: key))?.stage == .postProcessing
  }

  private func applyConversion(_ key: String, _ progress: Double) {
    guard owns(key) else { return }
    transition(Self.taskId(of: key)) { $0.withConversion(progress) }
  }
}
