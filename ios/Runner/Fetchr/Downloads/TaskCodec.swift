import Foundation

// `savedFile` is the saved file relative to Documents; savedUri is rebuilt from it per snapshot, because the app
// container's path changes between installs.
struct StoredTask: Equatable {
  var task: DownloadTask
  var savedFile: String?
}

// Android's TaskCodec JSON shape, except that `savedFile` replaces `savedUri`.
enum TaskCodec {
  // Nil when the list cannot be encoded: the store then keeps its last good file rather than an empty list. Only a
  // non-finite Double can make this fail, and TaskRecord never holds one.
  static func encode(_ tasks: [StoredTask]) -> Data? {
    try? JSONEncoder().encode(tasks.map(TaskRecord.init))
  }

  // Newest first; tasks created together keep their stored order.
  static func decode(_ data: Data) -> [StoredTask] {
    guard let records = try? JSONDecoder().decode([Lenient].self, from: data) else { return [] }
    return records.compactMap(\.record).enumerated()
      .sorted { a, b in
        a.element.createdAtMs != b.element.createdAtMs
          ? a.element.createdAtMs > b.element.createdAtMs : a.offset < b.offset
      }
      .map { StoredTask(task: TaskTransitions.onRestart($0.element.task), savedFile: $0.element.savedFile) }
  }
}

// One bad task is skipped instead of failing the whole list.
private struct Lenient: Decodable {
  let record: TaskRecord?

  init(from decoder: Decoder) throws {
    record = try? TaskRecord(from: decoder)
  }
}

// Enums are stored by Kotlin's constant names: pigeon's raw values are declaration indexes and would silently remap
// on a reorder. `stalled` is a live reading of the last progress line, so it is never stored.
private struct TaskRecord: Codable {
  var id: String
  var request: RequestRecord
  var status: String
  var progress: Double
  var etaSeconds: Int64
  var errorCode: String?
  var errorMessage: String?
  var savedFile: String?
  var savedPath: String?
  var createdAtMs: Int64
  var stage: String?
  var downloadedBytes: Int64?
  var totalBytes: Int64?
  var speedBytesPerSec: Int64?
  var finishedAtMs: Int64?

  init(_ s: StoredTask) {
    let t = s.task
    id = t.id
    request = RequestRecord(t.request)
    status = t.status.storedName
    progress = t.progress.isFinite ? t.progress : -1
    etaSeconds = t.etaSeconds
    errorCode = t.errorCode
    errorMessage = t.errorMessage
    savedFile = s.savedFile
    savedPath = t.savedPath
    createdAtMs = t.createdAtMs
    stage = t.stage.storedName
    downloadedBytes = t.downloadedBytes
    totalBytes = t.totalBytes
    speedBytesPerSec = t.speedBytesPerSec
    finishedAtMs = t.finishedAtMs
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id)
    request = try c.decode(RequestRecord.self, forKey: .request)
    status = try c.decode(String.self, forKey: .status)
    guard TaskStatus(storedName: status) != nil else {
      throw DecodingError.dataCorruptedError(forKey: .status, in: c, debugDescription: status)
    }
    progress = try c.decode(Double.self, forKey: .progress)
    etaSeconds = try c.decode(Int64.self, forKey: .etaSeconds)
    errorCode = try c.decodeIfPresent(String.self, forKey: .errorCode)
    errorMessage = try c.decodeIfPresent(String.self, forKey: .errorMessage)
    savedFile = try c.decodeIfPresent(String.self, forKey: .savedFile)
    savedPath = try c.decodeIfPresent(String.self, forKey: .savedPath)
    createdAtMs = try c.decode(Int64.self, forKey: .createdAtMs)
    stage = try c.decodeIfPresent(String.self, forKey: .stage)
    if let stage, TaskStage(storedName: stage) == nil {
      throw DecodingError.dataCorruptedError(forKey: .stage, in: c, debugDescription: stage)
    }
    downloadedBytes = try c.decodeIfPresent(Int64.self, forKey: .downloadedBytes)
    totalBytes = try c.decodeIfPresent(Int64.self, forKey: .totalBytes)
    speedBytesPerSec = try c.decodeIfPresent(Int64.self, forKey: .speedBytesPerSec)
    finishedAtMs = try c.decodeIfPresent(Int64.self, forKey: .finishedAtMs)
  }

  // Both names were checked when the record was decoded.
  var task: DownloadTask {
    DownloadTask(
      id: id, request: request.request, status: TaskStatus(storedName: status)!, progress: progress,
      etaSeconds: etaSeconds, errorCode: errorCode, errorMessage: errorMessage, savedUri: nil, savedPath: savedPath,
      createdAtMs: createdAtMs, stage: stage.flatMap(TaskStage.init(storedName:)) ?? .preparing,
      downloadedBytes: downloadedBytes, totalBytes: totalBytes, speedBytesPerSec: speedBytesPerSec, stalled: false,
      finishedAtMs: finishedAtMs)
  }
}

private struct RequestRecord: Codable {
  var url: String
  var title: String
  var thumbnail: String?
  var quality: String
  var folder: String
  var useAria2c: Bool
  var uploader: String?
  var durationSeconds: Int64?
  var playlistTitle: String?
  var playlistIndex: Int64?
  var playlistCount: Int64?

  init(_ r: DownloadRequest) {
    url = r.url
    title = r.title
    thumbnail = r.thumbnail
    quality = r.quality.storedName
    folder = r.folder
    useAria2c = r.useAria2c
    uploader = r.uploader
    durationSeconds = r.durationSeconds
    playlistTitle = r.playlistTitle
    playlistIndex = r.playlistIndex
    playlistCount = r.playlistCount
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    url = try c.decode(String.self, forKey: .url)
    title = try c.decode(String.self, forKey: .title)
    thumbnail = try c.decodeIfPresent(String.self, forKey: .thumbnail)
    quality = try c.decode(String.self, forKey: .quality)
    guard Quality(storedName: quality) != nil else {
      throw DecodingError.dataCorruptedError(forKey: .quality, in: c, debugDescription: quality)
    }
    folder = try c.decode(String.self, forKey: .folder)
    useAria2c = try c.decode(Bool.self, forKey: .useAria2c)
    uploader = try c.decodeIfPresent(String.self, forKey: .uploader)
    durationSeconds = try c.decodeIfPresent(Int64.self, forKey: .durationSeconds)
    playlistTitle = try c.decodeIfPresent(String.self, forKey: .playlistTitle)
    playlistIndex = try c.decodeIfPresent(Int64.self, forKey: .playlistIndex)
    playlistCount = try c.decodeIfPresent(Int64.self, forKey: .playlistCount)
  }

  var request: DownloadRequest {
    DownloadRequest(
      url: url, title: title, thumbnail: thumbnail, quality: Quality(storedName: quality)!, folder: folder,
      useAria2c: useAria2c, uploader: uploader, durationSeconds: durationSeconds, playlistTitle: playlistTitle,
      playlistIndex: playlistIndex, playlistCount: playlistCount)
  }
}

private protocol StoredName: CaseIterable, Equatable {
  var storedName: String { get }
}

extension StoredName {
  init?(storedName: String) {
    guard let match = Self.allCases.first(where: { $0.storedName == storedName }) else { return nil }
    self = match
  }
}

extension Quality: StoredName {
  fileprivate var storedName: String {
    switch self {
    case .best: "BEST"
    case .p1080: "P1080"
    case .p720: "P720"
    case .p480: "P480"
    case .mp3: "MP3"
    case .cover: "COVER"
    }
  }
}

extension TaskStatus: StoredName {
  fileprivate var storedName: String {
    switch self {
    case .queued: "QUEUED"
    case .running: "RUNNING"
    case .completed: "COMPLETED"
    case .failed: "FAILED"
    case .canceled: "CANCELED"
    case .paused: "PAUSED"
    }
  }
}

extension TaskStage: StoredName {
  fileprivate var storedName: String {
    switch self {
    case .preparing: "PREPARING"
    case .downloading: "DOWNLOADING"
    case .postProcessing: "POST_PROCESSING"
    }
  }
}
