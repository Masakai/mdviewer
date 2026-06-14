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
        false
    }

    func application(_: NSApplication, open urls: [URL]) {
        for url in urls {
            NotificationCenter.default.post(name: .openURLFromDelegate, object: url)
        }
    }

    @objc private func handleOpenLocalDocument(_ notification: Notification) {
        guard let url = notification.object as? URL else { return }
        openDocumentInNewTab(url: url)
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
    static let openURLFromDelegate = Notification.Name("MDViewer.openURLFromDelegate")
}
