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
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            NotificationCenter.default.post(name: .newFile, object: nil)
        }
        return true
    }

    func application(_: NSApplication, open urls: [URL]) {
        // 複数URLを同時に渡されても取りこぼさないよう、1URLにつき1つの独立したウィンドウで開く
        for url in urls {
            openDocumentInNewWindow(url: url)
        }
    }

    @objc private func handleOpenLocalDocument(_ notification: Notification) {
        guard let url = notification.object as? URL else { return }
        openDocumentInNewTab(url: url)
    }

    private func openDocumentInNewWindow(url: URL) {
        let hosting = NSHostingController(rootView: ContentView(initialURL: url))
        let window = NSWindow(contentViewController: hosting)
        window.setContentSize(NSSize(width: 960, height: 700))
        window.minSize = NSSize(width: 800, height: 600)
        window.title = url.lastPathComponent
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .unified
        window.tabbingMode = .disallowed
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
