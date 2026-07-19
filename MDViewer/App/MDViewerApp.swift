import SwiftUI

@main
struct MDViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .help) {
                Button("MDViewer Help") {
                    openWindow(id: "help")
                }
            }

            CommandGroup(replacing: .newItem) {
                Button("New") {
                    NotificationCenter.default.post(name: .newFile, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)

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

            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    NotificationCenter.default.post(name: .saveFile, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)
            }

            CommandMenu("View") {
                Button("Toggle Editor Mode") {
                    NotificationCenter.default.post(name: .toggleEditorMode, object: nil)
                }
                .keyboardShortcut("e", modifiers: .command)

                Divider()

                Button("Toggle Sidebar") {
                    NotificationCenter.default.post(name: .toggleSidebar, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

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

        Window("MDViewer Help", id: "help") {
            HelpView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 900, height: 700)
    }
}

// MARK: - Additional Notification names

extension Notification.Name {
    static let increaseFontSize = Notification.Name("MDViewer.increaseFontSize")
    static let decreaseFontSize = Notification.Name("MDViewer.decreaseFontSize")
    static let resetFontSize = Notification.Name("MDViewer.resetFontSize")
    static let exportPDF = Notification.Name("MDViewer.exportPDF")
    static let exportHTML = Notification.Name("MDViewer.exportHTML")
    static let pdfPageSizeChanged = Notification.Name("MDViewer.pdfPageSizeChanged")
    static let newFile = Notification.Name("MDViewer.newFile")
}

// MARK: - Help window

/// Markdown/Mermaid記法のリファレンスを表示する読み取り専用ウィンドウ。
/// DocumentViewModelには一切触れず、独自のRenderViewModel/SidebarViewModelで
/// 既存のレンダリングパイプライン（WebRendererView）を再利用する。
struct HelpView: View {
    @StateObject private var renderVM = RenderViewModel()
    @StateObject private var sidebarVM = SidebarViewModel()
    @State private var helpText: String = ""

    var body: some View {
        NavigationSplitView(
            sidebar: {
                SidebarView(sidebarVM: sidebarVM, renderVM: renderVM)
                    .frame(minWidth: 180, idealWidth: 220, maxWidth: 320)
            },
            detail: {
                WebRendererView(renderVM: renderVM, sidebarVM: sidebarVM)
                    .frame(minWidth: 500, minHeight: 400)
            }
        )
        .onAppear {
            helpText = Self.loadHelpMarkdown()
            renderVM.applyCurrentThemeAndFontSize()
            renderVM.renderMarkdown(helpText)
            sidebarVM.extractTOC(from: helpText)
        }
    }

    private static func loadHelpMarkdown() -> String {
        let languageCode = Locale.preferredLanguages.first?.hasPrefix("ja") == true ? "ja" : "en"
        let fileName = "help.\(languageCode)"
        guard
            let url = Bundle.main.url(forResource: fileName, withExtension: "md", subdirectory: "Web/help"),
            let contents = try? String(contentsOf: url, encoding: .utf8)
        else {
            return "# Help content not found"
        }
        return contents
    }
}
