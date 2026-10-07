import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = true
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
            if let existing = DocumentWindowRegistry.shared.window(for: url) {
                if existing.isMiniaturized {
                    existing.deminiaturize(nil)
                }
                existing.makeKeyAndOrderFront(nil)
            } else {
                openDocumentInNewWindow(url: url)
            }
        }
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
        // 既存のウィンドウに重ならないよう、少しずらして配置する
        if let key = NSApp.keyWindow {
            let point = window.cascadeTopLeft(from: NSPoint(x: key.frame.minX, y: key.frame.maxY))
            window.setFrameTopLeftPoint(point)
        }
        window.makeKeyAndOrderFront(nil)
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
        }
        window.makeKeyAndOrderFront(nil)
    }
}

extension Notification.Name {
    static let openNewDocumentWindow = Notification.Name("MDViewer.openNewDocumentWindow")
}
