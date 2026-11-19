import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  // One gate for every yt-dlp run (downloads, info calls) and the updater.
  private let gate = RunGate()
  private lazy var downloads = DownloadRepository(
    python: PythonRuntime.shared, documents: Paths.documentsDir, cachesDir: Paths.cachesDir,
    store: TaskStore(url: Paths.applicationSupportDir.appendingPathComponent("downloads.json")),
    pickedDir: Paths.pickedDir, gate: gate)
  private lazy var updater = YtDlpUpdater(
    root: Paths.ytDlpDir, session: YtDlpUpdater.makeSession(), gate: gate, defaults: .standard,
    compile: { dir in _ = try await PythonRuntime.shared.call("compile", ["dir": dir.path]) })
  private let startup = YtDlpStartup()
  private lazy var hostApi = HostApi(
    python: PythonRuntime.shared, downloads: downloads, gate: gate, updater: updater, startup: startup)

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    PythonRuntime.setEmitHandler { [downloads] task, json in downloads.receive(taskId: task, json: json) }
    // Tests run in this app: they get the bundled yt-dlp, write no launch record and never reach GitHub.
    if ProcessInfo.processInfo.environment["FETCHR_TESTING"] == "1" {
      PythonRuntime.shared.start()
    } else {
      PythonRuntime.shared.start(ytDlpDir: updater.launchChoice(bundled: YtDlpUpdater.bundledVersion()))
      startup.begin { [updater] in await YtDlpStartup.run(python: PythonRuntime.shared, updater: updater) }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()
    FetchrHostApiSetup.setUp(binaryMessenger: messenger, api: hostApi)
    DownloadsStreamHandler.register(with: messenger, streamHandler: DownloadsStream(repository: downloads))
  }
}
