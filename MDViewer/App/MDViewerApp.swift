import SwiftUI

@main
struct MDViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        // URLを開く処理はAppDelegateが担当する。SwiftUIが外部イベントごとに空ウィンドウを作らないようにする
        .handlesExternalEvents(matching: [])
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .help) {
                Button("MDViewer Help") {
                    openWindow(id: "help")
                }

                Button("Check for Updates…") {
                    // GitHub の最新リリースと比べて知らせる。入れ替えはせず、リリースページを開けるようにするだけ
                    Task { await UpdateChecker.shared.checkForUpdates() }
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

                OpenRecentMenu(recentDocuments: RecentDocuments.shared)
            }

            CommandGroup(after: .newItem) {
                Button("Reload") {
                    NotificationCenter.default.post(name: .reloadFile, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }

            CommandGroup(replacing: .saveItem) {
                Button("Close") {
                    NSApp.keyWindow?.performClose(nil)
                }
                .keyboardShortcut("w", modifiers: .command)

                Button("Save") {
                    NotificationCenter.default.post(name: .saveFile, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)
            }

            CommandGroup(replacing: .printItem) {
                // ドキュメントを表示していないウィンドウでは、受け取った ContentView 側で何もしない
                Button("Print…") {
                    NotificationCenter.default.post(name: .printDocument, object: nil)
                }
                .keyboardShortcut("p", modifiers: .command)
            }

            // 独自の CommandMenu("View") にすると、システムの「表示」メニュー（タブバーやフルスクリーンの項目が入る）と
            // 2つ並んでしまうので、システムの「表示」メニューに差し込む
            CommandGroup(before: .toolbar) {
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
                .background(WindowTabbingDisabler())
        }

        Window("MDViewer Help", id: "help") {
            HelpView()
                .background(WindowTabbingDisabler())
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .handlesExternalEvents(matching: [])
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
    static let previewFontsChanged = Notification.Name("MDViewer.previewFontsChanged")
    static let mathOptionsChanged = Notification.Name("MDViewer.mathOptionsChanged")
    /// object is nil: observers reload the theme preference from the settings.
    static let previewThemeChanged = Notification.Name("MDViewer.previewThemeChanged")
    /// object に文字サイズ（Double）を載せる。設定のスライダーを操作したときだけ送る。
    static let previewFontSizeChanged = Notification.Name("MDViewer.previewFontSizeChanged")
    static let newFile = Notification.Name("MDViewer.newFile")
    static let printDocument = Notification.Name("MDViewer.printDocument")
}

// MARK: - Window tabbing

/// 載ったウィンドウをタブに入れないようにする。ヘルプと設定のウィンドウがドキュメントのタブに混ざらないようにするために使う。
private struct WindowTabbingDisabler: NSViewRepresentable {
    final class AttachView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.tabbingMode = .disallowed
        }
    }

    func makeNSView(context _: Context) -> NSView {
        AttachView()
    }

    func updateNSView(_: NSView, context _: Context) {}
}

// MARK: - Open Recent menu

/// File > Open Recent。一覧の変化でメニューを作り直せるよう、View として一覧を監視する。
struct OpenRecentMenu: View {
    @ObservedObject var recentDocuments: RecentDocuments

    var body: some View {
        Menu("Open Recent") {
            let titles = RecentDocuments.menuTitles(for: recentDocuments.urls)
            ForEach(Array(zip(recentDocuments.urls, titles)), id: \.0) { url, title in
                Button {
                    NotificationCenter.default.post(name: .openRecentDocument, object: url)
                } label: {
                    Text(verbatim: title)
                }
            }

            Divider()

            Button("Clear Menu") {
                recentDocuments.clear()
            }
            .disabled(recentDocuments.urls.isEmpty)
        }
    }
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
                    .background(renderVM.theme.backgroundColor)
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
