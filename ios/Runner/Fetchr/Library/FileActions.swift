import QuickLook
import UIKit

// The library's share, preview and open-folder actions. Every file here is already checked to be inside Documents.
@MainActor
enum FileActions {
  static func share(_ file: URL, from presenter: UIViewController) {
    let sheet = UIActivityViewController(activityItems: [file], applicationActivities: nil)
    present(sheet, from: presenter)
  }

  static func preview(_ file: URL, from presenter: UIViewController) {
    present(FilePreview(file: file), from: presenter)
  }

  // .urlPathAllowed keeps ";", which older URL parsers read as the start of path parameters.
  private nonisolated static let pathCharacters = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: ";"))

  // The Files app at the file's folder; nil when that folder is gone. iOS cannot select the file itself, as on
  // Android.

  nonisolated static func folderURL(of file: URL) -> URL? {
    let folder = file.deletingLastPathComponent().path
    guard FileManager.default.isDirectory(atPath: folder) == true,
      let encoded = (folder.hasSuffix("/") ? folder : folder + "/").addingPercentEncoding(
        withAllowedCharacters: pathCharacters)
    else { return nil }
    return URL(string: "shareddocuments://" + encoded)
  }

  static func openFolder(of file: URL, opener: (URL) async -> Bool) async throws {
    guard let url = folderURL(of: file), await opener(url) else {
      throw FetchrError(code: "no_folder_app", message: "No app can open that folder.", details: nil)
    }
  }

  // The Flutter view controller, or what it already presents, so a second sheet does not fail to present.
  static func presenter() -> UIViewController? {
    let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
    var top = (windows.first(where: \.isKeyWindow) ?? windows.first)?.rootViewController
    while let next = top?.presentedViewController, !next.isBeingDismissed { top = next }
    return top
  }

  // An iPad shows these as popovers, which need an anchor; the centre of the view, with no arrow.
  private static func present(_ controller: UIViewController, from presenter: UIViewController) {
    if let popover = controller.popoverPresentationController {
      let bounds = presenter.view.bounds
      popover.sourceView = presenter.view
      popover.sourceRect = CGRect(x: bounds.midX, y: bounds.midY, width: 0, height: 0)
      popover.permittedArrowDirections = []
    }
    presenter.present(controller, animated: true)
  }
}

// Its own data source, because QLPreviewController holds its data source weakly.
private final class FilePreview: QLPreviewController, QLPreviewControllerDataSource {
  private let file: URL

  init(file: URL) {
    self.file = file
    super.init(nibName: nil, bundle: nil)
    dataSource = self
  }

  required init?(coder: NSCoder) { nil }

  func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

  func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
    file as NSURL
  }
}
