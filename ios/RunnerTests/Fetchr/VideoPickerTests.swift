import UIKit
import XCTest
@testable import Runner

// A presenter UIKit would refuse: present would be dropped and the picker's delegate never called.
private final class BusyPresenter: UIViewController {
  var presenting: UIViewController?
  var dismissing = false
  private(set) var presented = 0

  override var presentedViewController: UIViewController? { presenting }
  override var isBeingDismissed: Bool { dismissing }

  override func present(_ controller: UIViewController, animated: Bool, completion: (() -> Void)? = nil) {
    presented += 1
  }
}

@MainActor
final class VideoPickerTests: XCTestCase {
  private let dir = FileManager.default.temporaryDirectory.appendingPathComponent("picker-\(UUID().uuidString)")
  private var window: UIWindow?

  override func tearDown() async throws {
    window?.isHidden = true
    window = nil
  }

  // On screen, so the only reason left to refuse is the one each test sets.
  private func onScreen(_ presenter: UIViewController) throws {
    let scene = try XCTUnwrap(
      UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first, "the test host has no scene")
    let window = UIWindow(windowScene: scene)
    window.rootViewController = presenter
    window.isHidden = false
    self.window = window
    XCTAssertNotNil(presenter.viewIfLoaded?.window)
  }

  private func pickReturns(from presenter: UIViewController) async -> (done: Bool, url: URL?) {
    let finished = expectation(description: "pick returns")
    var result: URL?
    Task { @MainActor in
      result = try? await VideoPicker.pick(from: presenter, into: dir)
      finished.fulfill()
    }
    let outcome = await XCTWaiter().fulfillment(of: [finished], timeout: 2)
    return (outcome == .completed, result)
  }

  func testPickReturnsNilAtOnceWhenThePresenterIsPresenting() async throws {
    let presenter = BusyPresenter()
    try onScreen(presenter)
    presenter.presenting = UIViewController()
    let (done, url) = await pickReturns(from: presenter)
    XCTAssertTrue(done, "no continuation left waiting")
    XCTAssertNil(url)
    XCTAssertEqual(presenter.presented, 0)
  }

  func testPickReturnsNilAtOnceWhenThePresenterIsBeingDismissed() async throws {
    let presenter = BusyPresenter()
    try onScreen(presenter)
    presenter.dismissing = true
    let (done, url) = await pickReturns(from: presenter)
    XCTAssertTrue(done)
    XCTAssertNil(url)
    XCTAssertEqual(presenter.presented, 0)
  }

  func testPickReturnsNilAtOnceWhenThePresenterIsOffScreen() async {
    let presenter = BusyPresenter()
    let (done, url) = await pickReturns(from: presenter)
    XCTAssertTrue(done)
    XCTAssertNil(url)
    XCTAssertEqual(presenter.presented, 0)
  }

  func testLoadErrorIsLoggedByDomainAndCode() {
    let error = NSError(domain: NSItemProvider.errorDomain, code: NSItemProvider.ErrorCode.unavailableCoercionError.rawValue)
    XCTAssertEqual(VideoPicker.logLine(for: error), "\(NSItemProvider.errorDomain) -1200")
    XCTAssertEqual(VideoPicker.logLine(for: nil), "no error")
  }
}
