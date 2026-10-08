import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 直前に配置したドキュメントウィンドウ。続けて開くウィンドウをずらす基準にする。
    private weak var lastPlacedWindow: NSWindow?

    override init() {
        super.init()
        // SwiftUI は applicationDidFinishLaunching より先に最初のウィンドウを表示する。
        // 起動時の復元で送られる通知を取りこぼさないよう、生成時点で受信登録しておく。
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenLocalDocument(_:)),
            name: .openLocalDocument,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenNewDocumentWindow),
            name: .openNewDocumentWindow,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenDocumentInWindow(_:)),
            name: .openDocumentInWindow,
            object: nil
        )
    }

    func applicationDidFinishLaunching(_: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = true
    }

    func applicationWillTerminate(_: Notification) {
        // 終了に伴うウィンドウ閉鎖で、復元対象の一覧が消えないようにする
        OpenDocumentStore.shared.isTerminating = true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // ウィンドウが1つも無いときだけ新規ドキュメントを開く（最小化中のウィンドウは macOS が戻す）
        if !flag, !NSApp.windows.contains(where: \.isMiniaturized) {
            openNewDocumentWindow()
        }
        return true
    }

    func application(_: NSApplication, open urls: [URL]) {
        // 複数URLを同時に渡されても取りこぼさないよう、1URLにつき1つの独立したウィンドウで開く。
        // すでに開いているファイルは新しく開かず、既存のウィンドウを前面に出す。
        for url in urls {
            openOrActivateDocument(url: url)
        }
    }

    private func openOrActivateDocument(url: URL) {
        if let existing = DocumentWindowRegistry.shared.window(for: url) {
            if existing.isMiniaturized {
                existing.deminiaturize(nil)
            }
            existing.makeKeyAndOrderFront(nil)
        } else {
            openDocumentInNewWindow(url: url)
        }
    }

    @objc private func handleOpenDocumentInWindow(_ notification: Notification) {
        guard let url = notification.object as? URL else { return }
        openOrActivateDocument(url: url)
    }

    @objc private func handleOpenLocalDocument(_ notification: Notification) {
        guard let url = notification.object as? URL else { return }
        openDocumentInNewTab(url: url)
    }

    @objc private func handleOpenNewDocumentWindow() {
        openNewDocumentWindow()
    }

    /// 空の新規ドキュメントを、独立した新しいウィンドウで開く。
    private func openNewDocumentWindow() {
        let window = makeDocumentWindow(rootView: ContentView(startsAsNewDocument: true), title: "Untitled")
        place(window)
        window.makeKeyAndOrderFront(nil)
    }

    /// 新しいドキュメントウィンドウを配置する。
    /// 最前面のドキュメントウィンドウから1段ずらし、ドキュメントウィンドウが無ければ画面中央に置く。
    private func place(_ window: NSWindow) {
        // 複数ファイルを続けて開くと、アプリが非アクティブな間はキーウィンドウが切り替わらない。
        // 前面に並べた順で判定し、直前に配置したウィンドウ（登録前の場合がある）も基準に含める。
        let reference = NSApp.orderedWindows.first { candidate in
            candidate !== window && candidate.isVisible
                && (candidate === lastPlacedWindow || DocumentWindowRegistry.shared.contains(candidate))
        }
        if let reference, let screen = reference.screen ?? NSScreen.main {
            let point = WindowPlacement.cascadedTopLeft(
                from: reference.frame,
                windowSize: window.frame.size,
                visibleFrame: screen.visibleFrame
            )
            window.setFrameTopLeftPoint(point)
        } else {
            window.center()
        }
        lastPlacedWindow = window
    }

    private func makeDocumentWindow(rootView: ContentView, title: String) -> NSWindow {
        let hosting = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hosting)
        window.setContentSize(NSSize(width: 960, height: 700))
        window.minSize = NSSize(width: 800, height: 600)
        window.title = title
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .unified
        window.tabbingMode = .disallowed
        return window
    }

    private func openDocumentInNewWindow(url: URL) {
        let window = makeDocumentWindow(rootView: ContentView(initialURL: url), title: url.lastPathComponent)
        // ContentView が描画されて登録するまでの間に同じURLが来ても重複しないよう、先に登録する
        DocumentWindowRegistry.shared.register(window: window, url: url)
        place(window)
        window.makeKeyAndOrderFront(nil)
    }

    private func openDocumentInNewTab(url: URL) {
        let contentView = ContentView(initialURL: url)
        let hosting = NSHostingController(rootView: contentView)
        let window = NSWindow(contentViewController: hosting)
        window.setContentSize(NSSize(width: 960, height: 700))
        window.minSize = NSSize(width: 800, height: 600)
        window.title = url.lastPathComponent
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .unified

        if let keyWindow = NSApp.keyWindow {
            window.tabbingIdentifier = keyWindow.tabbingIdentifier
            keyWindow.addTabbedWindow(window, ordered: .above)
        } else {
            place(window)
        }
        window.makeKeyAndOrderFront(nil)
    }
}

extension Notification.Name {
    static let openNewDocumentWindow = Notification.Name("MDViewer.openNewDocumentWindow")
    /// object に URL を載せる。新しいウィンドウで開く（すでに開いていれば前面に出す）。
    static let openDocumentInWindow = Notification.Name("MDViewer.openDocumentInWindow")
}
