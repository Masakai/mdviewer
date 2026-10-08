import AppKit
import SwiftUI

struct ContentView: View {
    var initialURL: URL?
    /// true のとき、起動時に空の新規ドキュメントとして開く（File > New で作るウィンドウ用）。
    var startsAsNewDocument = false

    @StateObject private var documentVM = DocumentViewModel()
    @StateObject private var sidebarVM = SidebarViewModel()
    @StateObject private var renderVM = RenderViewModel()
    @StateObject private var exportVM = ExportViewModel()
    @StateObject private var windowBox = WindowBox()

    @AppStorage("sidebarWidth") private var sidebarWidth: Double = 240
    @AppStorage("isSidebarVisible") private var isSidebarVisible: Bool = true
    /// エディタモードはウィンドウごとの状態。新規ドキュメントを作っても他のウィンドウの表示を変えない。
    /// 最後に切り替えた状態だけを、次に開くウィンドウの初期値として保存する。
    @State private var isEditorMode: Bool = UserDefaults.standard.bool(forKey: "isEditorMode")

    var body: some View {
        NavigationSplitView(
            sidebar: {
                SidebarView(sidebarVM: sidebarVM, renderVM: renderVM)
                    .frame(minWidth: 180, idealWidth: sidebarWidth, maxWidth: 400)
            },
            detail: {
                Group {
                    if !documentVM.hasDocument {
                        WelcomeView(documentVM: documentVM, onNewFile: startNewDocumentInThisWindow)
                    } else {
                        HSplitView {
                            // エディタペイン: isEditorMode時のみ表示
                            if isEditorMode {
                                MarkdownEditorView(documentVM: documentVM)
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
        .onReceive(NotificationCenter.default.publisher(for: .reloadFile)) { _ in
            guard isKeyWindow else { return }
            documentVM.reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .saveFile)) { _ in
            guard isKeyWindow else { return }
            documentVM.save()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleEditorMode)) { _ in
            guard isKeyWindow else { return }
            isEditorMode.toggle()
            UserDefaults.standard.set(isEditorMode, forKey: "isEditorMode")
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { _ in
            // NavigationSplitView handles its own sidebar toggle
        }
        // Keyboard shortcuts via Commands are declared in MDViewerApp
        .navigationTitle(
            documentVM.fileURL.map { Text(verbatim: $0.lastPathComponent) }
                ?? (documentVM.hasDocument ? Text("Untitled") : Text("MDViewer"))
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
            } else {
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
private struct WindowCloseInterceptor: NSViewRepresentable {
    let documentVM: DocumentViewModel
    let windowBox: WindowBox

    func makeNSView(context _: Context) -> NSView {
        let view = WindowAttachView()
        let documentVM = documentVM
        // 起動時の復元が2件目以降のウィンドウを配置するとき、このウィンドウを基準にできるよう、
        // ウィンドウに載った時点で登録しておく（updateNSView の登録は非同期で間に合わない）
        view.onAttach = { window in
            DocumentWindowRegistry.shared.register(window: window) { documentVM.fileURL }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.documentVM = documentVM
        let documentVM = documentVM
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            window.delegate = context.coordinator
            windowBox.window = window
            // 表示中のファイルは切り替わりうるので、値ではなく都度参照する形で登録する
            DocumentWindowRegistry.shared.register(window: window) { documentVM.fileURL }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(documentVM: documentVM)
    }

    final class Coordinator: NSObject, NSWindowDelegate {
        var documentVM: DocumentViewModel

        init(documentVM: DocumentViewModel) {
            self.documentVM = documentVM
        }

        func windowWillClose(_: Notification) {
            // 閉じたファイルを次回起動時の復元対象から外す
            if let url = documentVM.fileURL {
                OpenDocumentStore.shared.remove(url: url)
            }
        }

        func windowShouldClose(_: NSWindow) -> Bool {
            guard documentVM.isDirty else { return true }

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
    static let reloadFile = Notification.Name("MDViewer.reloadFile")
    static let saveFile = Notification.Name("MDViewer.saveFile")
    static let toggleSidebar = Notification.Name("MDViewer.toggleSidebar")
    static let toggleEditorMode = Notification.Name("MDViewer.toggleEditorMode")
}
