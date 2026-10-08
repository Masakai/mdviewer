import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class DocumentViewModel: ObservableObject {
    @Published var text: String = ""
    @Published var fileURL: URL?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var isDirty: Bool = false
    @Published var hasDocument: Bool = false

    private let fileWatcher = FileWatcher()
    private let openDocumentStore: OpenDocumentStore

    init(openDocumentStore: OpenDocumentStore = .shared) {
        self.openDocumentStore = openDocumentStore
        fileWatcher.onChange = { [weak self] in
            Task { @MainActor in
                self?.reload()
            }
        }
    }

    func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = UTType.markdownFileTypes + [.plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url: url)
    }

    /// File > Open で選ばれたファイルを開く。
    /// ドキュメント表示中なら置き換えず別ウィンドウに回し、無ければこのウィンドウに読み込む。
    func open(url: URL) {
        if hasDocument {
            // 表示中のドキュメントを置き換えず、別ウィンドウで開く（開いていれば前面に出す）
            NotificationCenter.default.post(name: .openDocumentInWindow, object: url)
        } else {
            load(url: url)
        }
    }

    func load(url: URL) {
        isLoading = true
        errorMessage = nil

        do {
            let contents = try String(contentsOf: url, encoding: .utf8)
            fileURL = url
            text = contents
            isDirty = false
            hasDocument = true
            fileWatcher.start(url: url)
            BookmarkManager.shared.save(url: url)
            saveLastOpened(url: url)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// 新規の空Markdownドキュメントを開く。既存の未保存確認は呼び出し側（ContentView）で行う。
    func newDocument() {
        fileWatcher.stop()
        fileURL = nil
        text = ""
        isDirty = false
        hasDocument = true
    }

    func reload() {
        guard let url = fileURL else { return }
        do {
            let contents = try String(contentsOf: url, encoding: .utf8)
            isDirty = false
            text = contents
            // 一時的に消えたファイルが戻ってきた場合など、直前の読み込み失敗の
            // アラートが残らないようにする（成功時は常に最新の内容を表示している）
            if errorMessage != nil { errorMessage = nil }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateText(_ newText: String) {
        guard text != newText else { return }
        isDirty = true
        text = newText
    }

    func save() {
        guard let url = fileURL else {
            saveAs()
            return
        }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            isDirty = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.markdown]
        panel.nameFieldStringValue = "Untitled.md"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            fileURL = url
            isDirty = false
            fileWatcher.start(url: url)
            BookmarkManager.shared.save(url: url)
            saveLastOpened(url: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 前回終了時に開いていたファイルを復元する。このウィンドウに1件目を読み込み、残りは新しいウィンドウで開く。
    /// 復元は起動ごとに1回だけ行う（2つ目以降のウェルカム画面では何もしない）。
    func restoreLastOpened() {
        let urls = openDocumentStore.claimLaunchURLs()
        guard let first = urls.first else { return }
        load(url: first)
        for url in urls.dropFirst() {
            NotificationCenter.default.post(name: .openDocumentInWindow, object: url)
        }
    }

    private func saveLastOpened(url: URL) {
        openDocumentStore.add(url: url)
    }
}
