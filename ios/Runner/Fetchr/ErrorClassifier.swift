import Foundation

// An error from the Python bridge: `hint` is the code Python already knows (a disk-full or socket exception) and
// stands in for Kotlin's exception-type rules.
struct BridgeError: Error {
  let hint: String?
  let message: String
}

enum ErrorClassifier {
  private struct Rule {
    let code: String
    let text: NSRegularExpression
    let fallback: String

    init(_ code: String, _ pattern: String, _ fallback: String) {
      self.code = code
      // The patterns are constants, so a bad one is a programming error.
      text = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
      self.fallback = fallback
    }

    func matches(_ text: String) -> Bool {
      self.text.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
  }

  static let networkMessage = "No internet connection. Check your connection and try again."
  static let noStorageMessage = "Couldn't save the file. Free up space or allow storage access, then retry."
  static let unknownMessage = "Something went wrong. If it keeps happening, update yt-dlp in Settings."
  static let permissionDeniedMessage =
    "Fetchr can't save files. Allow storage access in the app settings, then retry."

  // Codes from Android's table that no text rule produces; Python may name them directly.
  private static let passThroughHints: Set<String> = ["invalid_url", "busy", "no_folder_app"]

  // Order matters: the first rule that matches wins.
  private static let rules = [
    Rule("no_storage", #"\bErrno 28\b|No space left|ENOSPC"#, noStorageMessage),
    Rule(
      "network",
      #"urlopen error|\bErrno (?:7|101|110|111)\b|timed out|Temporary failure in name resolution|Network is unreachable|Connection reset"#
        + #"|\bErrno (?:50|51|54|60|61|65)\b|nodename nor servname provided|Network is down|Connection refused"#,
      networkMessage),
    // After network: a blocked socket also reports Errno 13, inside a urlopen error.
    Rule("permission_denied", #"\bErrno 13\b|\bEACCES\b|Permission denied"#, permissionDeniedMessage),
    Rule("unsupported_site", #"Unsupported URL"#, "This site isn't supported."),
    Rule(
      "private_video", #"Private video|Sign in to confirm|members-only|Join this channel"#,
      "This video is private or needs a sign-in."),
    Rule(
      "unavailable",
      #"Video unavailable|This video is unavailable|has been removed|(?:not|made this video) available in your country|HTTP Error 404"#,
      "This video isn't available. It may have been removed or blocked in your region."),
  ]

  static func classify(_ error: Error) -> (code: String, message: String) {
    if let coded = error as? FetchrError { return (coded.code, coded.message ?? unknownMessage) }
    if let file = fileError(error) { return file }

    let bridged = error as? BridgeError
    let raw = bridged?.message ?? String(describing: error)
    let lines = raw.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    let errorLine = lines.last { $0.hasPrefix("ERROR:") }
      .map { $0.dropFirst("ERROR:".count).trimmingCharacters(in: .whitespacesAndNewlines) }
      .flatMap { $0.isEmpty ? nil : $0 }
    // Retry warnings earlier in stderr mention timeouts even when the final error is something else.
    let text = errorLine ?? raw

    let rule = rules.first { $0.matches(text) || bridged?.hint == $0.code }
    if rule == nil, let hint = bridged?.hint, passThroughHints.contains(hint) {
      return (hint, errorLine ?? lines.last ?? unknownMessage)
    }
    let message = errorLine ?? rule?.fallback ?? lines.last ?? unknownMessage
    return (rule?.code ?? "unknown", message)
  }
}

extension ErrorClassifier {
  // Saving into Documents fails with Cocoa or POSIX errors whose descriptions carry the container's absolute path,
  // which must never reach the user or a stored task.
  fileprivate static func fileError(_ error: Error) -> (code: String, message: String)? {
    let ns = error as NSError
    let posix = ns.domain == NSPOSIXErrorDomain ? ns.code
      : (ns.userInfo[NSUnderlyingErrorKey] as? NSError).flatMap { $0.domain == NSPOSIXErrorDomain ? $0.code : nil }
    if ns.domain == NSCocoaErrorDomain && ns.code == CocoaError.fileWriteOutOfSpace.rawValue || posix == Int(ENOSPC) {
      return ("no_storage", noStorageMessage)
    }
    if ns.domain == NSCocoaErrorDomain
      && [CocoaError.fileWriteNoPermission.rawValue, CocoaError.fileReadNoPermission.rawValue].contains(ns.code)
      || posix == Int(EACCES) || posix == Int(EPERM)
    {
      return ("permission_denied", permissionDeniedMessage)
    }
    if ns.domain == NSCocoaErrorDomain || ns.domain == NSPOSIXErrorDomain { return ("unknown", unknownMessage) }
    return nil
  }
}

extension FetchrError {
  static func from(_ error: Error) -> FetchrError {
    if let coded = error as? FetchrError { return coded }
    let (code, message) = ErrorClassifier.classify(error)
    return FetchrError(code: code, message: message, details: nil)
  }
}
