import Foundation

// Android's RunGate: an update swaps yt-dlp only while no run executes it, and a run that starts meanwhile waits.
actor RunGate {
  static let busy = FetchrError(code: "busy", message: "Finish or cancel downloads before updating yt-dlp.", details: nil)

  private var active = 0
  private var swapping = false
  private var waiting: [CheckedContinuation<Void, Never>] = []

  func enter() async {
    // Woken runs check again: another swap may have begun before they got back onto the actor.
    while swapping {
      await withCheckedContinuation { waiting.append($0) }
    }
    active += 1
  }

  func leave() {
    assert(active > 0, "leave() without enter()")
    active = max(0, active - 1)
  }

  func beginSwap() async throws {
    guard active == 0, !swapping else { throw Self.busy }
    swapping = true
  }

  func endSwap() {
    swapping = false
    let woken = waiting
    waiting = []
    woken.forEach { $0.resume() }
  }
}

extension PythonCalling {
  // A call that runs yt-dlp. The gate is held until Python returns, so an abandoned call still unwinding counts.
  func call(_ name: String, _ payload: [String: Any], gate: RunGate) async throws -> Any {
    await gate.enter()
    do {
      let value = try await call(name, payload)
      await gate.leave()
      return value
    } catch {
      await gate.leave()
      throw error
    }
  }
}
