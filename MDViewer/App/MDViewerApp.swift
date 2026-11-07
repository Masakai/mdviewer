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

                SaveMenuItem(keyDocument: KeyDocumentState.shared)

                DocumentFileMenuItems()
            }

            CommandGroup(replacing: .printItem) {
                Menu("Export") {
                    Button("Export as PDF…") {
                        NotificationCenter.default.post(name: .exportPDF, object: nil)
                    }
                    .keyboardShortcut("p", modifiers: [.command, .shift])

                    Button("Export as HTML…") {
                        NotificationCenter.default.post(name: .exportHTML, object: nil)
                    }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                }

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
                .keyboardShortcut("s", modifiers: [.command, .control])

                ThemeMenu()

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

            CommandGroup(after: .textEditing) {
                FindMenu()
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

// MARK: - Save menu item

/// File > Save。前面の文書が読み取り専用なら暗く表示して押せなくする（#37）。未編集かどうかでは無効にしない。
struct SaveMenuItem: View {
    @ObservedObject var keyDocument: KeyDocumentState

    var body: some View {
        Button("Save") {
            NotificationCenter.default.post(name: .saveFile, object: nil)
        }
        .keyboardShortcut("s", modifiers: .command)
        .disabled(keyDocument.isReadOnly)
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

// MARK: - File menu items

/// File > Duplicate / Save As… / Rename… / Move To…。
/// 名前の変更と移動はファイルのあるときだけ使える。前面のウィンドウのビューモデルが取れないとき
/// （AppDelegate が作るウィンドウでは届かない場合がある）は有効にしておき、受け取った側で何もしない。
struct DocumentFileMenuItems: View {
    @FocusedObject private var documentVM: DocumentViewModel?

    var body: some View {
        Button("Duplicate") {
            NotificationCenter.default.post(name: .duplicateDocument, object: nil)
        }
        .keyboardShortcut("s", modifiers: [.command, .shift])

        // SwiftUI のメニューでは Option で入れ替わる代替項目にできないので、「複製」と並べて表示する
        Button("Save As…") {
            NotificationCenter.default.post(name: .saveFileAs, object: nil)
        }
        .keyboardShortcut("s", modifiers: [.command, .shift, .option])

        Button("Rename…") {
            NotificationCenter.default.post(name: .renameFile, object: nil)
        }
        .disabled(documentVM.map { $0.fileURL == nil } ?? false)

        Button("Move To…") {
            NotificationCenter.default.post(name: .moveFile, object: nil)
        }
        .disabled(documentVM.map { $0.fileURL == nil } ?? false)
    }
}

// MARK: - Theme menu

/// View > Theme。ツールバーのテーマのメニューと同じ項目を、前面のウィンドウに対して選ぶ。
/// チェックは前面のウィンドウのビューモデルが取れたときだけ付く。選んだ値は通知で前面のウィンドウに送る。
struct ThemeMenu: View {
    @FocusedObject private var renderVM: RenderViewModel?

    var body: some View {
        Menu("Theme") {
            Toggle("Use Settings Theme", isOn: Binding(
                get: { renderVM.map { $0.windowThemeOverride == nil } ?? false },
                set: { isOn in
                    if isOn { NotificationCenter.default.post(name: .selectWindowTheme, object: nil) }
                }
            ))

            Divider()

            ForEach(MarkdownTheme.all) { theme in
                Toggle(theme.displayName, isOn: Binding(
                    get: { renderVM?.windowThemeOverride == theme },
                    set: { isOn in
                        if isOn { NotificationCenter.default.post(name: .selectWindowTheme, object: theme) }
                    }
                ))
            }
        }
    }
}

// MARK: - Find menu

/// Edit > Find。
struct FindMenu: View {
    var body: some View {
        Menu("Find") {
            Button("Find…") {
                NotificationCenter.default.post(name: .showSearchBar, object: nil)
            }
            .keyboardShortcut("f", modifiers: .command)

            Button("Find and Replace…") {
                NotificationCenter.default.post(name: .showFindAndReplace, object: nil)
            }
            .keyboardShortcut("f", modifiers: [.command, .option])

            Button("Find Next") {
                NotificationCenter.default.post(name: .findNextMatch, object: nil)
            }
            .keyboardShortcut("g", modifiers: .command)

            Button("Find Previous") {
                NotificationCenter.default.post(name: .findPreviousMatch, object: nil)
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])
        }
    }
}
