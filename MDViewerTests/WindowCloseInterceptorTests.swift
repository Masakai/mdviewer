import AppKit
import XCTest
@testable import MDViewer

@MainActor
final class WindowCloseInterceptorTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "WindowCloseInterceptorTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        try await super.tearDown()
    }

    /// ファイルを読み込んでいない（fileURL が nil の）ので、閉じても OpenDocumentStore には触れない。
    private func makeCoordinator() -> WindowCloseInterceptor.Coordinator {
        let documentVM = DocumentViewModel(openDocumentStore: OpenDocumentStore(defaults: defaults), settings: defaults)
        return WindowCloseInterceptor.Coordinator(documentVM: documentVM)
    }

    func test_windowWillClose_removesWindowFromRegistry() {
        let coordinator = makeCoordinator()
        let window = NSWindow()
        window.isReleasedWhenClosed = false
        let url = URL(fileURLWithPath: "/tmp/WindowCloseInterceptorTests-\(UUID().uuidString).md")
        DocumentWindowRegistry.shared.register(window: window, url: url)
        defer { DocumentWindowRegistry.shared.register(window: window, url: nil) }

        coordinator.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: window))

        XCTAssertNil(DocumentWindowRegistry.shared.window(for: url))
        XCTAssertFalse(DocumentWindowRegistry.shared.contains(window))
        XCTAssertTrue(coordinator.didClose)
    }

    func test_windowWillClose_keepsOtherWindowsRegistered() {
        let coordinator = makeCoordinator()
        let closing = NSWindow()
        closing.isReleasedWhenClosed = false
        let other = NSWindow()
        other.isReleasedWhenClosed = false
        let otherURL = URL(fileURLWithPath: "/tmp/WindowCloseInterceptorTests-\(UUID().uuidString).md")
        DocumentWindowRegistry.shared.register(window: closing, url: URL(fileURLWithPath: "/tmp/closing.md"))
        DocumentWindowRegistry.shared.register(window: other, url: otherURL)
        defer {
            DocumentWindowRegistry.shared.register(window: closing, url: nil)
            DocumentWindowRegistry.shared.register(window: other, url: nil)
        }

        coordinator.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: closing))

        XCTAssertTrue(DocumentWindowRegistry.shared.window(for: otherURL) === other)
    }
}
