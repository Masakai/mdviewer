import AppKit
import XCTest
@testable import MDViewer

final class DocumentWindowRegistryTests: XCTestCase {
    func test_登録したウィンドウを同じURLで取得できる() {
        let registry = DocumentWindowRegistry()
        let window = NSWindow()
        let url = URL(fileURLWithPath: "/tmp/a.md")
        registry.register(window: window, url: url)
        XCTAssertTrue(registry.window(for: url) === window)
    }

    func test_未登録のURLはnilを返す() {
        let registry = DocumentWindowRegistry()
        registry.register(window: NSWindow(), url: URL(fileURLWithPath: "/tmp/a.md"))
        XCTAssertNil(registry.window(for: URL(fileURLWithPath: "/tmp/b.md")))
    }

    func test_パスの表記ゆれを同一ファイルとして扱う() {
        let registry = DocumentWindowRegistry()
        let window = NSWindow()
        registry.register(window: window, url: URL(fileURLWithPath: "/tmp/a.md"))
        XCTAssertTrue(registry.window(for: URL(fileURLWithPath: "/tmp/sub/../a.md")) === window)
    }

    func test_ウィンドウが別のファイルに切り替わると古いURLでは見つからない() {
        let registry = DocumentWindowRegistry()
        let window = NSWindow()
        let old = URL(fileURLWithPath: "/tmp/a.md")
        let new = URL(fileURLWithPath: "/tmp/b.md")
        registry.register(window: window, url: old)
        registry.register(window: window, url: new)
        XCTAssertNil(registry.window(for: old))
        XCTAssertTrue(registry.window(for: new) === window)
    }

    func test_URLをnilで登録すると記録が消える() {
        let registry = DocumentWindowRegistry()
        let window = NSWindow()
        let url = URL(fileURLWithPath: "/tmp/a.md")
        registry.register(window: window, url: url)
        registry.register(window: window, url: nil)
        XCTAssertNil(registry.window(for: url))
    }
}

extension DocumentWindowRegistryTests {
    func test_urlProvider登録は最新のURLで照合する() {
        let registry = DocumentWindowRegistry()
        let window = NSWindow()
        var current: URL? = URL(fileURLWithPath: "/tmp/a.md")
        registry.register(window: window) { current }
        XCTAssertTrue(registry.window(for: URL(fileURLWithPath: "/tmp/a.md")) === window)
        current = URL(fileURLWithPath: "/tmp/b.md")
        XCTAssertNil(registry.window(for: URL(fileURLWithPath: "/tmp/a.md")))
        XCTAssertTrue(registry.window(for: URL(fileURLWithPath: "/tmp/b.md")) === window)
        current = nil
        XCTAssertNil(registry.window(for: URL(fileURLWithPath: "/tmp/b.md")))
    }
}
