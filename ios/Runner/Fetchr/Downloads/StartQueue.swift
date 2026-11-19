// Starts at most `max` runs at once, in an order the user can change. Keys name runs, not tasks: a resumed task's
// new run can queue before its old one is gone.
struct StartQueue {
  private let max: Int
  private var waiting: [String] = []
  private var running: Set<String> = []

  init(max: Int) { self.max = max }

  // Run keys, not task ids; the task list is where Dart reads the start order from.
  var order: [String] { waiting }

  // Called when the run is created, not when it reaches its turn, so a reorder sent right after sees it.
  mutating func add(_ key: String) { waiting.append(key) }

  // The waiting runs of `taskIds` take the places those runs held, in the order of `taskIds`; the rest keep theirs.
  mutating func reorder(taskIds: [String], taskOf: (String) -> String) {
    waiting.swapSlots(taskIds, id: taskOf)
  }

  // The first waiting run that is `ready`, if a slot is free; it holds the slot until `remove(_:)`. A run that is
  // not ready keeps its place.
  mutating func next(where ready: (String) -> Bool = { _ in true }) -> String? {
    guard running.count < max, let index = waiting.firstIndex(where: ready) else { return nil }
    let key = waiting.remove(at: index)
    running.insert(key)
    return key
  }

  // A run that ends gives its place or its slot up, whichever it holds; an unknown key or a second call frees nothing.
  mutating func remove(_ key: String) {
    waiting.removeAll { $0 == key }
    running.remove(key)
  }
}

extension Array {
  // The items of `ids` that `movable` lets through take the places those items hold, in the order of `ids`; the
  // rest keep theirs. The one reorder rule, for the start queue and for the task list Dart reads the order from.
  mutating func swapSlots(
    _ ids: [String], id: (Element) -> String, movable: (Element) -> Bool = { _ in true }
  ) {
    var rank: [String: Int] = [:]
    for (index, key) in ids.enumerated() { rank[key] = index }
    let slots = indices.filter { rank[id(self[$0])] != nil && movable(self[$0]) }
    let moved = slots.map { self[$0] }.sorted { rank[id($0)]! < rank[id($1)]! }
    for (slot, item) in zip(slots, moved) { self[slot] = item }
  }
}
