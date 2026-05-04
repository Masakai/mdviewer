import SwiftUI

@main
struct MDViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") {
                    NotificationCenter.default.post(name: .openFile, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandGroup(after: .newItem) {
                Button("Reload") {
                    NotificationCenter.default.post(name: .reloadFile, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }

            CommandMenu("View") {
                Button("Toggle Sidebar") {
                    NotificationCenter.default.post(name: .toggleSidebar, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Button("TOC Mode") {
                    NotificationCenter.default.post(name: .setSidebarModeTOC, object: nil)
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("Thumbnails Mode") {
                    NotificationCenter.default.post(name: .setSidebarModeThumbnails, object: nil)
                }
                .keyboardShortcut("2", modifiers: .command)

                Divider()

                Button("Find…") {
                    NotificationCenter.default.post(name: .showSearchBar, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)

                Divider()

                Button("Increase Font Size") {
                    NotificationCenter.default.post(name: .increaseFontSize, object: nil)
                }
                .keyboardShortcut("+", modifiers: .command)

                Button("Decrease Font Size") {
                    NotificationCenter.default.post(name: .decreaseFontSize, object: nil)
                }
                .keyboardShortcut("-", modifiers: .command)

                Button("Reset Font Size") {
                    NotificationCenter.default.post(name: .resetFontSize, object: nil)
                }
                .keyboardShortcut("0", modifiers: .command)
            }

            CommandMenu("Export") {
                Button("Export as PDF…") {
                    NotificationCenter.default.post(name: .exportPDF, object: nil)
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])

                Button("Export as HTML…") {
                    NotificationCenter.default.post(name: .exportHTML, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }

        Settings {
            PreferencesView()
        }
    }
}

// MARK: - Additional Notification names

extension Notification.Name {
    static let setSidebarModeTOC        = Notification.Name("MDViewer.setSidebarModeTOC")
    static let setSidebarModeThumbnails = Notification.Name("MDViewer.setSidebarModeThumbnails")
    static let increaseFontSize         = Notification.Name("MDViewer.increaseFontSize")
    static let decreaseFontSize         = Notification.Name("MDViewer.decreaseFontSize")
    static let resetFontSize            = Notification.Name("MDViewer.resetFontSize")
    static let exportPDF                = Notification.Name("MDViewer.exportPDF")
    static let exportHTML               = Notification.Name("MDViewer.exportHTML")
    static let pdfPageSizeChanged       = Notification.Name("MDViewer.pdfPageSizeChanged")
}
