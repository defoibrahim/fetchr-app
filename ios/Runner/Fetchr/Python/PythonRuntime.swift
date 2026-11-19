import Foundation
import os

protocol PythonCalling: Sendable {
  func call(_ name: String, _ payload: [String: Any]) async throws -> Any
}

final class PythonRuntime: PythonCalling, @unchecked Sendable {
  // Takes the installed yt-dlp to run (nil: the bundled copy), returns nil once Python is up, or why it is not.
  typealias Boot = @Sendable (URL?) -> String?
  // Takes the call name and its JSON payload, returns Python's JSON reply envelope.
  typealias Call = @Sendable (String, String) throws -> String

  private enum State {
    case idle
    case booting([CheckedContinuation<Void, Error>])
    case ready
    case failed(String)
  }

  // CPython initialises once per process, so the real interpreter only ever has this instance.
  static let shared = PythonRuntime(boot: { bootInterpreter(ytDlpDir: $0) }, call: { try callInterpreter($0, $1) })

  private static let emitQueue = DispatchQueue(label: "com.defo.fetchr.python.emit")
  private static let emitLock = NSLock()
  nonisolated(unsafe) private static var emitHandler: (@Sendable (String, String) -> Void)?

  private let boot: Boot
  private let invoke: Call
  private let lock = NSLock()
  private var state = State.idle

  init(boot: @escaping Boot, call: @escaping Call) {
    self.boot = boot
    self.invoke = call
  }

  // Only the first call boots; a call's yt-dlp dir is used only by that one.
  func start(ytDlpDir: URL? = nil) {
    let shouldBoot: Bool = lock.withLock {
      guard case .idle = state else { return false }
      state = .booting([])
      return true
    }
    guard shouldBoot else { return }

    let thread = Thread(block: { [self] in
      let began = Date()
      let error = boot(ytDlpDir)
      let elapsed = Int(Date().timeIntervalSince(began) * 1000)
      if let error {
        Log.python.error("Python failed to start after \(elapsed) ms: \(error, privacy: .public)")
      } else {
        Log.python.notice("Python ready in \(elapsed) ms")
      }
      finishBoot(error)
      // Python's threading.main_thread() is this thread; it must stay alive or threading's shutdown and
      // the interpreter's own bookkeeping misbehave.
      DispatchSemaphore(value: 0).wait()
    })
    // Secondary threads default to 512 KB, too little for deep Python recursion; this matches the main thread.
    thread.stackSize = 8 << 20
    thread.qualityOfService = .userInitiated
    thread.name = "com.defo.fetchr.python.boot"
    thread.start()
  }

  func call(_ name: String, _ payload: [String: Any]) async throws -> Any {
    guard JSONSerialization.isValidJSONObject(payload),
      let data = try? JSONSerialization.data(withJSONObject: payload),
      let json = String(data: data, encoding: .utf8)
    else {
      throw BridgeError(hint: nil, message: "The \(name) call has a payload that is not JSON.")
    }
    try await ready()
    let reply = try await withCheckedThrowingContinuation { continuation in
      // A thread per call, so a long download never queues a fetchInfo behind it.
      let thread = Thread { [invoke] in
        continuation.resume(with: Result { try invoke(name, json) })
      }
      thread.stackSize = 8 << 20
      thread.qualityOfService = .userInitiated
      thread.name = "com.defo.fetchr.python.call"
      thread.start()
    }
    return try Self.decode(reply)
  }

  static func setEmitHandler(_ handler: (@Sendable (_ taskId: String, _ json: String) -> Void)?) {
    emitLock.withLock { emitHandler = handler }
  }

  private func ready() async throws {
    start()
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      lock.withLock {
        switch state {
        case .idle:
          preconditionFailure("start() leaves the idle state")
        case .booting(let waiting):
          state = .booting(waiting + [continuation])
        case .ready:
          continuation.resume()
        case .failed(let error):
          continuation.resume(throwing: Self.bootFailure(error))
        }
      }
    }
  }

  private func finishBoot(_ error: String?) {
    let waiting: [CheckedContinuation<Void, Error>] = lock.withLock {
      guard case .booting(let waiting) = state else { return [] }
      state = error.map(State.failed) ?? .ready
      return waiting
    }
    for continuation in waiting {
      if let error {
        continuation.resume(throwing: Self.bootFailure(error))
      } else {
        continuation.resume()
      }
    }
  }

  private static func bootFailure(_ error: String) -> BridgeError {
    BridgeError(hint: nil, message: "Python failed to start: \(error)")
  }

  private static func decode(_ reply: String) throws -> Any {
    guard let envelope = try? JSONSerialization.jsonObject(with: Data(reply.utf8)) as? [String: Any] else {
      throw BridgeError(hint: nil, message: "Python returned a reply that is not JSON: \(reply.prefix(200))")
    }
    if envelope["ok"] as? Bool == true {
      return envelope["value"] ?? NSNull()
    }
    let message = (envelope["message"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    throw BridgeError(hint: envelope["hint"] as? String, message: message ?? ErrorClassifier.unknownMessage)
  }
}

extension PythonRuntime {
  private static let pythonEmit: fetchr_emit_fn = { taskId, json in
    guard let taskId, let json else { return }
    let task = String(cString: taskId)
    let body = String(cString: json)
    guard let handler = emitLock.withLock({ emitHandler }) else { return }
    // Python is waiting on this call, so the handler runs later on its own queue.
    emitQueue.async { handler(task, body) }
  }

  private static func bootInterpreter(ytDlpDir: URL?) -> String? {
    let bundle = Bundle.main.bundlePath
    let libs = "\(bundle)/python/lib"
    guard let version = try? FileManager.default.contentsOfDirectory(atPath: libs).first(where: { $0.hasPrefix("python3.") })
    else { return "no python3.x standard library in \(libs)" }
    let lib = "\(libs)/\(version)"
    // An installed update goes after the bridge, so it can never shadow fetchr_bridge, and ahead of app_packages,
    // so its yt_dlp and yt_dlp_ejs win whole. selftest.load drops it again if it fails to import.
    let update = ytDlpDir.map { [$0.path] } ?? []
    let paths = ["\(bundle)/app"] + update + ["\(bundle)/app_packages", lib, "\(lib)/lib-dynload"]

    fetchr_py_set_emit(pythonEmit)
    let cPaths = paths.map { strdup($0) }
    defer { cPaths.forEach { free($0) } }
    var error: UnsafeMutablePointer<CChar>?
    let status = cPaths.map { UnsafePointer($0) }.withUnsafeBufferPointer { buffer in
      fetchr_py_init("\(bundle)/python", buffer.baseAddress, Int32(buffer.count), ytDlpDir?.path, &error)
    }
    defer { fetchr_py_free(error) }
    guard status != 0 else { return nil }
    return error.map { String(cString: $0) } ?? "fetchr_py_init failed with no message"
  }

  private static func callInterpreter(_ name: String, _ payload: String) throws -> String {
    var error: UnsafeMutablePointer<CChar>?
    let reply = fetchr_py_call(name, payload, &error)
    defer {
      fetchr_py_free(reply)
      fetchr_py_free(error)
    }
    guard let reply else {
      throw BridgeError(hint: nil, message: error.map { String(cString: $0) } ?? "Python returned no reply")
    }
    return String(cString: reply)
  }
}
