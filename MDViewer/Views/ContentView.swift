import AppKit
import SwiftUI

struct ContentView: View {
    var initialURL: URL?
    /// true のとき、起動時に空の新規ドキュメントとして開く（File > New で作るウィンドウ用）。
    var startsAsNewDocument = false
    /// false のとき、前回終了時のファイルを復元しない（最後のドキュメントを閉じた後のウェルカム画面用）。
    var restoresLastOpened = true
    /// startsAsNewDocument のときの初期内容と保存パネルの初期名（File > Duplicate で作るウィンドウ用）。
    var initialText: String?
    var suggestedFileName: String?

    @StateObject private var documentVM = DocumentViewModel()
    @StateObject private var sidebarVM = SidebarViewModel()
    @StateObject private var renderVM = RenderViewModel()
    @StateObject private var exportVM = ExportViewModel()
    @StateObject private var windowBox = WindowBox()
    @StateObject private var editorSearch = EditorSearchController()

    @AppStorage("sidebarWidth") private var sidebarWidth: Double = 240
    @AppStorage("isSidebarVisible") private var isSidebarVisible: Bool = true
    /// エディタモードはウィンドウごとの状態。新規ドキュメントを作っても他のウィンドウの表示を変えない。
    /// 最後に切り替えた状態だけを、次に開くウィンドウの初期値として保存する。
    @State private var isEditorMode: Bool = UserDefaults.standard.bool(forKey: "isEditorMode")
    /// サイドバーの開閉。ツールバーのボタンやドラッグで閉じた場合もここに反映されるので、メニューと食い違わない。
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var search = SearchBarState()

    var body: some View {
        NavigationSplitView(
            columnVisibility: $columnVisibility,
            sidebar: {
                SidebarView(sidebarVM: sidebarVM, renderVM: renderVM)
                    .frame(minWidth: 180, idealWidth: sidebarWidth, maxWidth: 400)
            },
            detail: {
                Group {
                    if !documentVM.hasDocument {
                        WelcomeView(documentVM: documentVM, onNewFile: startNewDocumentInThisWindow)
                    } else {
                        VStack(spacing: 0) {
                            // 検索バーはエディタとプレビューの上に1本だけ出す
                            if search.isVisible {
                                SearchBarView(
                                    searchText: $search.text,
                                    replaceText: $search.replaceText,
                                    isVisible: $search.isVisible,
                                    target: search.target,
                                    focusRequest: search.focusRequest,
                                    renderVM: renderVM,
                                    editorSearch: editorSearch
                                )
                                .transition(.move(edge: .top).combined(with: .opacity))
                            }

                            HSplitView {
                                // エディタペイン: isEditorMode時のみ表示
                                if isEditorMode {
                                    MarkdownEditorView(
                                        documentVM: documentVM,
                                        previewFontSize: renderVM.fontSize,
                                        editorSearch: editorSearch
                                    )
                                    .frame(minWidth: 250)
                                }
                                // プレビューペイン: 常にマウントしておく（破棄しない）
                                MarkdownRenderView(
                                    documentVM: documentVM,
                                    renderVM: renderVM,
                                    sidebarVM: sidebarVM
                                )
                                .frame(minWidth: 250)
                            }
                        }
                        .animation(.easeInOut(duration: 0.15), value: search.isVisible)
                    }
                }
            }
        )
        .background(WindowCloseInterceptor(documentVM: documentVM, windowBox: windowBox))
        .toolbar {
            MainToolbar(documentVM: documentVM, renderVM: renderVM, exportVM: exportVM, isEditorMode: isEditorMode)
        }
        .onReceive(NotificationCenter.default.publisher(for: .newFile)) { _ in
            guard isKeyWindow else { return }
            requestNewDocument()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFile)) { _ in
            guard isKeyWindow else { return }
            documentVM.openFile()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openRecentDocument)) { notification in
            guard isKeyWindow, let url = notification.object as? URL else { return }
            documentVM.open(url: url)
        }
        .onReceive(NotificationCenter.default.publisher(for: .reloadFile)) { _ in
            guard isKeyWindow else { return }
            documentVM.reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .saveFile)) { _ in
            guard isKeyWindow else { return }
            documentVM.save()
        }
        .onReceive(NotificationCenter.default.publisher(for: .printDocument)) { _ in
            guard isKeyWindow, documentVM.hasDocument, let webView = renderVM.webView else { return }
            exportVM.print(webView: webView)
        }
        .modifier(SearchCommand(
            windowBox: windowBox,
            documentVM: documentVM,
            editorSearch: editorSearch,
            isEditorMode: isEditorMode,
            search: $search
        ))
        .modifier(DocumentFileCommands(
            windowBox: windowBox,
            documentVM: documentVM,
            renderVM: renderVM
        ))
        .modifier(FindNavigationCommands(
            windowBox: windowBox,
            documentVM: documentVM,
            renderVM: renderVM,
            editorSearch: editorSearch,
            isEditorMode: isEditorMode,
            search: $search
        ))
        .modifier(FontSizeAndExportCommands(
            windowBox: windowBox,
            documentVM: documentVM,
            renderVM: renderVM,
            exportVM: exportVM
        ))
        .onReceive(NotificationCenter.default.publisher(for: .toggleEditorMode)) { _ in
            guard isKeyWindow else { return }
            isEditorMode.toggle()
            UserDefaults.standard.set(isEditorMode, forKey: "isEditorMode")
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { _ in
            guard isKeyWindow else { return }
            // ツールバーのボタンやドラッグで開いたときに .all 以外の値になっても切り替えられるよう、閉じているかどうかだけで判定する
            columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
        }
        // Keyboard shortcuts via Commands are declared in MDViewerApp
        .navigationTitle(
            documentVM.fileURL.map { Text(verbatim: $0.lastPathComponent) }
                ?? (documentVM.hasDocument ? Text("Untitled") : Text("Welcome"))
        )
        .frame(minWidth: 800, minHeight: 600)
        .alert("Error", isPresented: Binding(
            get: { documentVM.errorMessage != nil },
            set: { if !$0 { documentVM.errorMessage = nil } }
        )) {
            Button("OK") { documentVM.errorMessage = nil }
        } message: {
            Text(documentVM.errorMessage ?? "")
        }
        .alert("preview_error_title", isPresented: Binding(
            get: { renderVM.renderFailureMessage != nil },
            set: { if !$0 { renderVM.renderFailureMessage = nil } }
        )) {
            Button("OK") { renderVM.renderFailureMessage = nil }
        } message: {
            Text(renderVM.renderFailureMessage ?? "")
        }
        .onAppear {
            if let url = initialURL {
                documentVM.load(url: url)
            } else if startsAsNewDocument {
                startNewDocumentInThisWindow()
                if let initialText {
                    documentVM.newDocument(duplicating: initialText, suggestedFileName: suggestedFileName)
                }
            } else if restoresLastOpened {
                documentVM.restoreLastOpened()
            }
        }
    }

    /// メニュー操作の通知は全ウィンドウに届くため、キーウィンドウの ContentView だけが処理する。
    private var isKeyWindow: Bool {
        windowBox.window?.isKeyWindow == true
    }

    /// File > New / ツールバーの New。開いているドキュメントには触れず、新しいウィンドウで開く。
    /// ドキュメントを開いていない（ウェルカム画面の）ウィンドウは、そのまま新規ドキュメントにする。
    private func requestNewDocument() {
        if documentVM.hasDocument {
            NotificationCenter.default.post(name: .openNewDocumentWindow, object: nil)
        } else {
            startNewDocumentInThisWindow()
        }
    }

    /// このウィンドウを空の新規ドキュメントにして、編集モードにする。
    private func startNewDocumentInThisWindow() {
        documentVM.newDocument()
        isEditorMode = true
    }
}

// MARK: - Search command

/// 検索バーの開閉と入力。ウィンドウごとに持つ。
struct SearchBarState {
    var isVisible = false
    var text = ""
    var replaceText = ""
    var target: SearchTarget = .preview
    /// ⌘F が押された回数。開いたまま押し直したときに検索欄へ入力を戻すのに使う。
    var focusRequest = 0
}

/// 表示 > 検索…（⌘F）。そのときエディタに入力があればエディタを、そうでなければプレビューを
/// 件数と移動の対象にする。検索欄に入力があるとき（開いたまま押し直したとき）は対象を変えない。
struct SearchCommand: ViewModifier {
    let windowBox: WindowBox
    let documentVM: DocumentViewModel
    let editorSearch: EditorSearchController
    let isEditorMode: Bool
    @Binding var search: SearchBarState

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .showSearchBar)) { _ in
                // メニューの通知は全ウィンドウに届くので、前面のウィンドウ（タブ）だけで開く
                guard let window = windowBox.window, window.isKeyWindow, documentVM.hasDocument else { return }
                search.target = Self.target(
                    editorHasFocus: isEditorMode && editorSearch.isTextViewFirstResponder,
                    searchFieldHasFocus: search.isVisible && window.firstResponder is NSTextView,
                    current: search.target
                )
                withAnimation { search.isVisible = true }
                search.focusRequest += 1
            }
            .onChange(of: isEditorMode) { _, isEditorMode in
                if !isEditorMode, search.target == .editor {
                    search.target = .preview
                }
            }
    }

    /// エディタを先に調べる。エディタも NSTextView なので、検索欄（のフィールドエディタ）と区別できない。
    static func target(editorHasFocus: Bool, searchFieldHasFocus: Bool, current: SearchTarget) -> SearchTarget {
        if editorHasFocus { return .editor }
        if searchFieldHasFocus { return current }
        return .preview
    }
}

// MARK: - Font size and export commands

/// 表示メニューの文字サイズと、書き出しメニューの項目の通知を処理する。
/// ContentView の body に直接並べると型チェックが終わらなくなるため分けている。
private struct FontSizeAndExportCommands: ViewModifier {
    let windowBox: WindowBox
    let documentVM: DocumentViewModel
    let renderVM: RenderViewModel
    let exportVM: ExportViewModel

    private var isKeyWindow: Bool {
        windowBox.window?.isKeyWindow == true
    }

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .increaseFontSize)) { _ in
                guard isKeyWindow else { return }
                renderVM.increaseFontSize()
            }
            .onReceive(NotificationCenter.default.publisher(for: .decreaseFontSize)) { _ in
                guard isKeyWindow else { return }
                renderVM.decreaseFontSize()
            }
            .onReceive(NotificationCenter.default.publisher(for: .resetFontSize)) { _ in
                guard isKeyWindow else { return }
                renderVM.resetFontSize()
            }
            .onReceive(NotificationCenter.default.publisher(for: .exportPDF)) { _ in
                guard isKeyWindow, documentVM.hasDocument, let webView = renderVM.webView else { return }
                exportVM.exportToPDF(webView: webView, sourceURL: documentVM.fileURL)
            }
            .onReceive(NotificationCenter.default.publisher(for: .exportHTML)) { _ in
                guard isKeyWindow, documentVM.hasDocument, let webView = renderVM.webView else { return }
                exportVM.exportToHTML(webView: webView, sourceURL: documentVM.fileURL)
            }
    }
}

// MARK: - Window box

/// ContentView が載っているウィンドウへの弱参照。キーウィンドウかどうかの判定に使う。
final class WindowBox: ObservableObject {
    weak var window: NSWindow?
}

// MARK: - Window close interceptor

/// ウィンドウに載ったときに通知する NSView。
private final class WindowAttachView: NSView {
    var onAttach: ((NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            onAttach?(window)
        }
    }
}

/// NSViewRepresentable that attaches an NSWindowDelegate to block window close when there are unsaved changes.
struct WindowCloseInterceptor: NSViewRepresentable {
    let documentVM: DocumentViewModel
    let windowBox: WindowBox

    func makeNSView(context _: Context) -> NSView {
        let view = WindowAttachView()
        let documentVM = documentVM
        // 起動時の復元が2件目以降のウィンドウを配置するとき、このウィンドウを基準にできるよう、
        // ウィンドウに載った時点で登録しておく（updateNSView の登録は非同期で間に合わない）
        view.onAttach = { window in
            DocumentWindowRegistry.shared.register(window: window) { documentVM.fileURL }
            // WindowGroup が作る最初のウィンドウにも、AppDelegate が作るウィンドウと同じタブの識別子を付ける
            window.tabbingIdentifier = DocumentWindowRegistry.tabbingIdentifier
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.documentVM = documentVM
        let documentVM = documentVM
        DispatchQueue.main.async {
            // 閉じた後の更新でレジストリに登録し直さない
            guard let window = nsView.window, !context.coordinator.didClose else { return }
            window.delegate = context.coordinator
            windowBox.window = window
            // SwiftUI が WindowGroup のウィンドウに自前の識別子を付け直しても保てるよう、更新のたびに付け直す
            if window.tabbingIdentifier != DocumentWindowRegistry.tabbingIdentifier {
                window.tabbingIdentifier = DocumentWindowRegistry.tabbingIdentifier
            }
            // 表示中のファイルは切り替わりうるので、値ではなく都度参照する形で登録する
            DocumentWindowRegistry.shared.register(window: window) { documentVM.fileURL }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(documentVM: documentVM)
    }

    final class Coordinator: NSObject, NSWindowDelegate {
        var documentVM: DocumentViewModel
        private(set) var didClose = false

        init(documentVM: DocumentViewModel) {
            self.documentVM = documentVM
        }

        func windowWillClose(_ notification: Notification) {
            didClose = true
            // 閉じたウィンドウはすぐにレジストリから外す。弱参照の解放を待つと、閉じた直後に同じファイルを
            // 開いたとき、閉じたウィンドウを前面に出そうとして開けない
            if let window = notification.object as? NSWindow {
                DocumentWindowRegistry.shared.register(window: window, url: nil)
            }
            NotificationCenter.default.post(
                name: .documentWindowWillClose,
                object: nil,
                userInfo: ["hasDocument": documentVM.hasDocument]
            )
            // 閉じたファイルを次回起動時の復元対象から外す
            if let url = documentVM.fileURL {
                OpenDocumentStore.shared.remove(url: url)
            }
        }

        func windowShouldClose(_ window: NSWindow) -> Bool {
            guard documentVM.isDirty else { return true }

            // タブグループをまとめて閉じると背景のタブにも確認が出るので、どのタブの確認か分かるよう前面にする
            if let tabGroup = window.tabGroup, tabGroup.selectedWindow !== window {
                tabGroup.selectedWindow = window
            }

            let alert = NSAlert()
            alert.messageText = NSLocalizedString("unsaved_changes_title", comment: "")
            alert.informativeText = NSLocalizedString("unsaved_changes_message", comment: "")
            alert.addButton(withTitle: NSLocalizedString("save_button", comment: ""))
            alert.addButton(withTitle: NSLocalizedString("discard_button", comment: ""))
            alert.addButton(withTitle: NSLocalizedString("cancel_button", comment: ""))
            alert.alertStyle = .warning

            let response = alert.runModal()
            switch response {
            case .alertFirstButtonReturn:
                documentVM.save()
                return documentVM.errorMessage == nil
            case .alertSecondButtonReturn:
                return true
            default:
                return false
            }
        }
    }
}

// MARK: - Welcome screen

struct WelcomeView: View {
    let documentVM: DocumentViewModel
    let onNewFile: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 64))
                .foregroundColor(.secondary)

            Text("MDViewer")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Open a Markdown file to get started")
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                Button("New File") {
                    onNewFile()
                }
                .keyboardShortcut("n", modifiers: .command)
                .buttonStyle(.borderedProminent)

                Button("Open File…") {
                    documentVM.openFile()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onDrop(of: [.markdown, .plainText, .fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadFileRepresentation(forTypeIdentifier: "public.file-url") { url, _ in
                guard let url else { return }
                DispatchQueue.main.async {
                    documentVM.load(url: url)
                }
            }
            return true
        }
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let openFile = Notification.Name("MDViewer.openFile")
    /// object に開くファイルの URL を載せる。
    static let openRecentDocument = Notification.Name("MDViewer.openRecentDocument")
    static let reloadFile = Notification.Name("MDViewer.reloadFile")
    static let saveFile = Notification.Name("MDViewer.saveFile")
    static let toggleSidebar = Notification.Name("MDViewer.toggleSidebar")
    static let toggleEditorMode = Notification.Name("MDViewer.toggleEditorMode")
}

// MARK: - Document window state

/// ウィンドウのタイトルのプロキシアイコン（representedURL）と未保存の印（isDocumentEdited）を、
/// 表示中のファイルと未保存状態に合わせる。ウィンドウに載った時点と、値が変わるたびに反映する。
private struct DocumentWindowStateView: NSViewRepresentable {
    let fileURL: URL?
    let isDirty: Bool

    final class StateView: NSView {
        var fileURL: URL?
        var isDirty = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        func apply() {
            guard let window else { return }
            if window.representedURL != fileURL {
                window.representedURL = fileURL
            }
            if window.isDocumentEdited != isDirty {
                window.isDocumentEdited = isDirty
            }
        }
    }

    func makeNSView(context _: Context) -> StateView {
        let view = StateView()
        view.fileURL = fileURL
        view.isDirty = isDirty
        return view
    }

    func updateNSView(_ nsView: StateView, context _: Context) {
        nsView.fileURL = fileURL
        nsView.isDirty = isDirty
        nsView.apply()
    }
}

// MARK: - File menu commands

/// ファイルメニューの 複製・別名で保存・名前を変更・移動 と、表示メニューのテーマの通知を処理する。
/// プロキシアイコンと未保存の印もここで付ける。前面のメニューから選んだ値を受けられるよう、
/// このウィンドウのビューモデルを focusedSceneObject で渡す。
private struct DocumentFileCommands: ViewModifier {
    let windowBox: WindowBox
    @ObservedObject var documentVM: DocumentViewModel
    let renderVM: RenderViewModel

    private var isKeyWindow: Bool {
        windowBox.window?.isKeyWindow == true
    }

    func body(content: Content) -> some View {
        content
            .background(DocumentWindowStateView(fileURL: documentVM.fileURL, isDirty: documentVM.isDirty))
            .focusedSceneObject(documentVM)
            .focusedSceneObject(renderVM)
            .onReceive(NotificationCenter.default.publisher(for: .duplicateDocument)) { _ in
                guard isKeyWindow, documentVM.hasDocument else { return }
                NotificationCenter.default.post(
                    name: .openNewDocumentWindow,
                    object: nil,
                    userInfo: [
                        "text": documentVM.text,
                        "suggestedFileName": DocumentViewModel.duplicateFileName(for: documentVM.fileURL),
                    ]
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: .saveFileAs)) { _ in
                guard isKeyWindow, documentVM.hasDocument else { return }
                documentVM.saveAs()
            }
            .onReceive(NotificationCenter.default.publisher(for: .renameFile)) { _ in
                guard isKeyWindow else { return }
                documentVM.renameFile()
            }
            .onReceive(NotificationCenter.default.publisher(for: .moveFile)) { _ in
                guard isKeyWindow else { return }
                documentVM.moveFile()
            }
            .onReceive(NotificationCenter.default.publisher(for: .selectWindowTheme)) { notification in
                guard isKeyWindow else { return }
                if let theme = notification.object as? MarkdownTheme {
                    renderVM.setTheme(theme)
                } else {
                    renderVM.useSettingsTheme()
                }
            }
    }
}

// MARK: - Find menu commands

/// 編集 > 検索 の 検索と置換・次を検索・前を検索。
private struct FindNavigationCommands: ViewModifier {
    let windowBox: WindowBox
    let documentVM: DocumentViewModel
    let renderVM: RenderViewModel
    let editorSearch: EditorSearchController
    let isEditorMode: Bool
    @Binding var search: SearchBarState

    private var isKeyWindow: Bool {
        windowBox.window?.isKeyWindow == true
    }

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .showFindAndReplace)) { _ in
                guard isKeyWindow, documentVM.hasDocument else { return }
                // エディタモードでなければ置換できないので、⌘F と同じにする
                guard isEditorMode else {
                    NotificationCenter.default.post(name: .showSearchBar, object: nil)
                    return
                }
                search.target = .editor
                withAnimation { search.isVisible = true }
                search.focusRequest += 1
            }
            .onReceive(NotificationCenter.default.publisher(for: .findNextMatch)) { _ in
                guard canMove else { return }
                switch search.target {
                case .editor: editorSearch.findNext()
                case .preview: renderVM.findNext()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .findPreviousMatch)) { _ in
                guard canMove else { return }
                switch search.target {
                case .editor: editorSearch.findPrevious()
                case .preview: renderVM.findPrevious()
                }
            }
    }

    private var canMove: Bool {
        isKeyWindow && documentVM.hasDocument && search.isVisible && !search.text.isEmpty
    }
}

extension Notification.Name {
    static let duplicateDocument = Notification.Name("MDViewer.duplicateDocument")
    static let saveFileAs = Notification.Name("MDViewer.saveFileAs")
    static let renameFile = Notification.Name("MDViewer.renameFile")
    static let moveFile = Notification.Name("MDViewer.moveFile")
    /// object に MarkdownTheme を載せる。nil なら設定のテーマに戻す。
    static let selectWindowTheme = Notification.Name("MDViewer.selectWindowTheme")
    static let showFindAndReplace = Notification.Name("MDViewer.showFindAndReplace")
    static let findNextMatch = Notification.Name("MDViewer.findNextMatch")
    static let findPreviousMatch = Notification.Name("MDViewer.findPreviousMatch")
}
