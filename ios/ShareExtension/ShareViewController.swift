import UIKit
import UniformTypeIdentifiers

// Hands the first shared link to Fetchr the way receive_sharing_intent's host side reads it: a JSON list of
// SharedMediaFile in the App Group's UserDefaults under "ShareKey", then the "ShareMedia-<app id>:share" URL, which
// opens the app; Home then fetches the link's formats. The plugin's own controller is not linked here, because it
// would bring Flutter into the extension.
final class ShareViewController: UIViewController {
  private static let sharedKey = "ShareKey"
  private static let messageKey = "ShareMessageKey"

  // "com.defo.fetchr.ShareExtension" belongs to "com.defo.fetchr".
  private var hostBundleId: String {
    let id = Bundle.main.bundleIdentifier ?? ""
    return id.split(separator: ".").dropLast().joined(separator: ".")
  }

  private var groupId: String {
    Bundle.main.object(forInfoDictionaryKey: "AppGroupId") as? String ?? "group.\(hostBundleId)"
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .clear
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    Task { await share() }
  }

  private func share() async {
    guard let (value, type) = await firstLink(),
      let data = try? JSONSerialization.data(withJSONObject: [["path": value, "type": type]]),
      let defaults = UserDefaults(suiteName: groupId)
    else {
      finish()
      return
    }
    defaults.set(data, forKey: Self.sharedKey)
    defaults.removeObject(forKey: Self.messageKey)
    if let url = URL(string: "ShareMedia-\(hostBundleId):share") { openHostApp(url) }
    finish()
  }

  // A web URL first; text that holds one (YouTube shares "title https://…") goes as text, and Dart picks the link.
  private func firstLink() async -> (String, String)? {
    let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
    for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
      if let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL,
        let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https"
      {
        return (url.absoluteString, "url")
      }
    }
    for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
      if let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String,
        !text.isEmpty
      {
        return (text, "text")
      }
    }
    return nil
  }

  // An extension has no UIApplication.shared; the host app's UIApplication is up the responder chain.
  private func openHostApp(_ url: URL) {
    var responder: UIResponder? = self
    while let current = responder {
      if let application = current as? UIApplication {
        application.open(url, options: [:], completionHandler: nil)
        return
      }
      responder = current.next
    }
  }

  private func finish() {
    extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
  }
}
