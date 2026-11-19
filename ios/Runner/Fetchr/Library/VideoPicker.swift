import PhotosUI
import UIKit
import UniformTypeIdentifiers
import os

// The photo picker, which runs out of process and needs no photo-library permission. The chosen video is copied to
// picked/<uuid>/<its name>.<ext>: the picker's own file is gone once its callback returns, and the name becomes the
// MP3's.
@MainActor
enum VideoPicker {
  static func pick(from presenter: UIViewController, into dir: URL = Paths.pickedDir) async throws -> URL? {
    // UIKit drops a present from a controller that is already presenting, going away or off screen, and the
    // delegate would then never end the pick.
    guard presenter.presentedViewController == nil, !presenter.isBeingDismissed, !presenter.isBeingPresented,
      presenter.viewIfLoaded?.window != nil
    else {
      Log.picker.notice("Picker not shown: the presenter is busy")
      return nil
    }
    var config = PHPickerConfiguration()
    config.filter = .videos
    config.selectionLimit = 1
    // The original file: a compatible one would be transcoded first, and only its audio is kept.
    config.preferredAssetRepresentationMode = .current
    let picker = PHPickerViewController(configuration: config)
    let session = PickerSession()
    picker.delegate = session
    // A swipe down may close the picker without calling its delegate.
    picker.presentationController?.delegate = session
    let provider: NSItemProvider? = await withCheckedContinuation { continuation in
      session.finish = { continuation.resume(returning: $0) }
      presenter.present(picker, animated: true)
    }
    withExtendedLifetime(session) {}
    guard let provider else { return nil }
    return try await copy(provider, into: dir)
  }

  private nonisolated static func copy(_ provider: NSItemProvider, into dir: URL) async throws -> URL {
    let type =
      provider.registeredTypeIdentifiers.first { UTType($0)?.conforms(to: .movie) == true } ?? UTType.movie.identifier
    let suggested = provider.suggestedName
    return try await withCheckedThrowingContinuation { continuation in
      _ = provider.loadFileRepresentation(forTypeIdentifier: type) { file, error in
        guard let file else {
          Log.picker.error("Picked video unreadable: \(logLine(for: error), privacy: .public)")
          continuation.resume(throwing: unreadable)
          return
        }
        do {
          continuation.resume(returning: try place(file, named: suggested, type: type, in: dir))
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  // The domain and code only: a description can carry the asset's path or name.
  nonisolated static func logLine(for error: Error?) -> String {
    guard let error else { return "no error" }
    let ns = error as NSError
    return "\(ns.domain) \(ns.code)"
  }

  private nonisolated static let unreadable = FetchrError(
    code: "unavailable", message: "The video could not be read.", details: nil)

  private nonisolated static func place(_ file: URL, named suggested: String?, type: String, in dir: URL) throws -> URL {
    let own = file.pathExtension
    // The same rule as LocalVideo's, so stage names its copy after this file.
    let ext = RequestBuilder.isSafeExtension(own) ? own : (UTType(type)?.preferredFilenameExtension ?? "mov")
    let stem = RequestBuilder.safeFileName(suggested ?? file.deletingPathExtension().lastPathComponent)
    let folder = dir.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let target = folder.appendingPathComponent("\(stem).\(ext.lowercased())", isDirectory: false)
    do {
      try FileManager.default.copyItem(at: file, to: target)
    } catch {
      try? FileManager.default.removeItem(at: folder)
      throw error
    }
    return target
  }
}

// Ends the pick once, whichever way the picker closes.
private final class PickerSession: NSObject, PHPickerViewControllerDelegate, UIAdaptivePresentationControllerDelegate {
  var finish: ((NSItemProvider?) -> Void)?

  func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    picker.dismiss(animated: true)
    end(results.first?.itemProvider)
  }

  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    end(nil)
  }

  private func end(_ provider: NSItemProvider?) {
    let finish = self.finish
    self.finish = nil
    finish?(provider)
  }
}
