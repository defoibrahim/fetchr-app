import Foundation

// Mirrors the Kotlin `str`/`num`/`long` extensions: a JSON null and a missing key both read as absent.
struct JSONObject {
  private let dict: [String: Any]

  init(_ dict: [String: Any]) {
    self.dict = dict
  }

  static func parse(_ json: String) throws -> JSONObject {
    let value = try JSONSerialization.jsonObject(with: Data(json.utf8), options: [.fragmentsAllowed])
    guard let dict = value as? [String: Any] else { throw JSONObjectError.notAnObject }
    return JSONObject(dict)
  }

  // Like org.json's optString, a number reads as its text.
  func str(_ key: String) -> String? {
    switch dict[key] {
    case let text as String: return text
    case let number as NSNumber: return number.isBool ? (number.boolValue ? "true" : "false") : number.stringValue
    default: return nil
    }
  }

  func num(_ key: String) -> Double? {
    guard let number = dict[key] as? NSNumber, !number.isBool else { return nil }
    return number.doubleValue
  }

  // yt-dlp reports fractional durations (213.886).
  func long(_ key: String) -> Int64? {
    num(key).map(roundToLong)
  }

  // org.json's optBoolean: true only for a JSON true or the text "true".
  func bool(_ key: String) -> Bool {
    switch dict[key] {
    case let number as NSNumber: return number.isBool && number.boolValue
    case let text as String: return text.lowercased() == "true"
    default: return false
    }
  }

  func objects(_ key: String) -> [JSONObject] {
    guard let array = dict[key] as? [Any] else { return [] }
    return array.compactMap { ($0 as? [String: Any]).map(JSONObject.init) }
  }
}

enum JSONObjectError: Error {
  case notAnObject
}

// Kotlin's roundToLong: ties go towards positive infinity, and the result saturates at the Long range.
func roundToLong(_ value: Double) -> Int64 {
  let floor = value.rounded(.down)
  let rounded = value - floor >= 0.5 ? floor + 1 : floor
  if rounded >= 0x1p63 { return .max }
  if rounded <= -0x1p63 { return .min }
  return Int64(rounded)
}

private extension NSNumber {
  var isBool: Bool { CFGetTypeID(self) == CFBooleanGetTypeID() }
}
