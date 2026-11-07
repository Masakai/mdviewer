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
    /// 表示中のファイルに書き込めない（Finder でロック・書き込み権限なし）。新規ドキュメントでは false。
    @Published private(set) var isReadOnly: Bool = false
    /// 未保存のドキュメントを初めて保存するときに、保存パネルへ入れておく名前（複製したドキュメント用）。
    var suggestedFileName: String?

    /// 設定 > 一般 のスイッチ。未設定のときはどちらもオン。
    nonisolated static let restoreOnLaunchKey = "restoreLastFile"
    nonisolated static let autoReloadKey = "autoReload"

    private let fileWatcher = FileWatcher()
    private let openDocumentStore: OpenDocumentStore
    private let settings: UserDefaults
    private let recentDocuments: RecentDocuments

    init(
        openDocumentStore: OpenDocumentStore = .shared,
        settings: UserDefaults = .standard,
        recentDocuments: RecentDocuments? = nil
    ) {
        self.openDocumentStore = openDocumentStore
        self.settings = settings
        // .shared は MainActor 上にあり、既定引数（非隔離の文脈で評価される）には書けないので、ここで補う
        self.recentDocuments = recentDocuments ?? .shared
        fileWatcher.onChange = { [weak self] in
            Task { @MainActor in
                self?.fileDidChange()
            }
        }
    }

    /// 表示中のファイルがディスク上で変わったとき。
    /// 自動再読み込みがオフなら表示を変えない（⌘R で読み直せる）。設定はその都度読むので、切り替えは即座に効く。
    func fileDidChange() {
        // 読み込み直さない設定でも、保存できるかどうかは最新にしておく
        refreshReadOnly()
        guard isEnabled(Self.autoReloadKey) else { return }
        reload()
    }

    private func isEnabled(_ key: String) -> Bool {
        // 起動引数（-autoReload NO など）では文字列で入るので、bool(forKey:) で読む
        settings.object(forKey: key) == nil ? true : settings.bool(forKey: key)
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
    /// 別のウィンドウですでに開いているファイルは、このウィンドウに読み込まずそのウィンドウを前面に出す。
    func open(url: URL) {
        if hasDocument || DocumentWindowRegistry.shared.window(for: url) != nil {
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
            refreshReadOnly()
            fileWatcher.start(url: url)
            BookmarkManager.shared.save(url: url)
            saveLastOpened(url: url)
            recentDocuments.note(url: url)
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
        suggestedFileName = nil
        hasDocument = true
        refreshReadOnly()
    }

    func reload() {
        guard let url = fileURL else { return }
        do {
            let contents = try String(contentsOf: url, encoding: .utf8)
            isDirty = false
            text = contents
            refreshReadOnly()
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
        // 書き込み権限のないファイルでも、フォルダに書き込めれば atomic な書き込み（一時ファイルを rename）は
        // 成功して中身が置き換わってしまうので、書く前に確かめる。isDirty は残し、閉じるときの確認で失われないようにする
        refreshReadOnly()
        if isReadOnly {
            errorMessage = String(
                format: NSLocalizedString("read_only_save_failed_message", comment: ""),
                url.lastPathComponent
            )
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
        // 保存済みのファイルがあればその名前を、複製した未保存の書類なら複製用の名前を初期値にする
        panel.nameFieldStringValue = fileURL?.lastPathComponent ?? suggestedFileName ?? "Untitled.md"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            fileURL = url
            isDirty = false
            refreshReadOnly()
            suggestedFileName = nil
            fileWatcher.start(url: url)
            BookmarkManager.shared.save(url: url)
            saveLastOpened(url: url)
            recentDocuments.note(url: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 表示中のファイルに書き込めるかを調べ直す。Finder でのロックや権限の変更はファイル監視では
    /// 届かないので、アプリが前面に戻ったときにも呼ぶ。調べられなかったときは書き込めるものとして扱う。
    func refreshReadOnly() {
        let readOnly: Bool
        if var url = fileURL {
            // URL は取得した値を run loop が1周するまで保持するので、変更直後でも読み直す
            url.removeCachedResourceValue(forKey: .isWritableKey)
            readOnly = (try? url.resourceValues(forKeys: [.isWritableKey]))?.isWritable == false
        } else {
            readOnly = false
        }
        if isReadOnly != readOnly {
            isReadOnly = readOnly
        }
    }

    /// 前回終了時に開いていたファイルを復元する。このウィンドウに1件目を読み込み、残りは新しいウィンドウで開く。
    /// 復元は起動ごとに1回だけ行う（2つ目以降のウェルカム画面では何もしない）。
    func restoreLastOpened() {
        // 復元しない設定でも一覧は取り出しておき、起動ごとに1回だけという扱いを変えない
        let urls = openDocumentStore.claimLaunchURLs()
        guard isEnabled(Self.restoreOnLaunchKey), let first = urls.first else { return }
        load(url: first)
        for url in urls.dropFirst() {
            NotificationCenter.default.post(name: .openDocumentInWindow, object: url)
        }
    }

    private func saveLastOpened(url: URL) {
        openDocumentStore.add(url: url)
    }
}

// MARK: - Duplicate, rename, move

enum DocumentRelocationError: LocalizedError, Equatable {
    case invalidName
    case alreadyExists(String)

    var errorDescription: String? {
        switch self {
        case .invalidName:
            return NSLocalizedString("rename_invalid_name", comment: "")
        case let .alreadyExists(name):
            return String(format: NSLocalizedString("relocate_already_exists %@", comment: ""), name)
        }
    }
}

extension DocumentViewModel {
    /// 複製したドキュメントとして、このウィンドウを未保存の新規ドキュメントにする。
    func newDocument(duplicating contents: String, suggestedFileName: String?) {
        newDocument()
        text = contents
        isDirty = true
        self.suggestedFileName = suggestedFileName
    }

    /// 複製の保存パネルに出す名前。「a.md」なら「a copy.md」。ファイルが無ければ「Untitled copy.md」。
    nonisolated static func duplicateFileName(for url: URL?) -> String {
        let base = url?.deletingPathExtension().lastPathComponent ?? NSLocalizedString("Untitled", comment: "")
        let ext = url?.pathExtension ?? ""
        let name = String(format: NSLocalizedString("%@ copy", comment: ""), base)
        return name + "." + (ext.isEmpty ? "md" : ext)
    }

    /// 同じフォルダ内で名前を変えた先の URL。拡張子を省いた名前には元の拡張子を付ける。
    /// 空の名前や、フォルダをまたぐ名前（/ や : を含む、. や ..）は nil。
    nonisolated static func renamedURL(from url: URL, newName: String) -> URL? {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != ".", name != "..",
              !name.contains("/"), !name.contains(":") else { return nil }
        let folder = url.deletingLastPathComponent()
        let ext = url.pathExtension
        if (name as NSString).pathExtension.isEmpty, !ext.isEmpty {
            return folder.appendingPathComponent(name).appendingPathExtension(ext)
        }
        return folder.appendingPathComponent(name)
    }

    /// 別のフォルダへ同じ名前のまま移した先の URL。
    nonisolated static func movedURL(from url: URL, toFolder folder: URL) -> URL {
        folder.appendingPathComponent(url.lastPathComponent)
    }

    /// 表示中のファイルを newURL へ移し（改名を含む）、監視・復元一覧・最近使った項目を新しい場所に合わせる。
    /// 同じ場所なら何もしない。移動先に別のファイルがあれば上書きせずエラーにする。
    func relocate(to newURL: URL) throws {
        guard let oldURL = fileURL else { return }
        let newURL = newURL.standardizedFileURL
        guard newURL != oldURL.standardizedFileURL else { return }
        if FileManager.default.fileExists(atPath: newURL.path),
           !Self.isSameFile(oldURL, newURL) {
            throw DocumentRelocationError.alreadyExists(newURL.lastPathComponent)
        }
        // 移動で古いパスの監視が反応して読み直さないよう、先に止める
        fileWatcher.stop()
        do {
            try FileManager.default.moveItem(at: oldURL, to: newURL)
        } catch {
            fileWatcher.start(url: oldURL)
            throw error
        }
        fileURL = newURL
        // 移動先の権限で書き込めるかが変わりうるので読み直す
        refreshReadOnly()
        fileWatcher.start(url: newURL)
        BookmarkManager.shared.save(url: newURL)
        openDocumentStore.remove(url: oldURL)
        openDocumentStore.add(url: newURL)
        recentDocuments.note(url: newURL)
    }

    /// 大文字・小文字を区別しないボリュームで大文字小文字だけを変える改名を、衝突と見なさないための判定。
    /// URL はリソース値をキャッシュするので、パスから作り直して比べる。
    private nonisolated static func isSameFile(_ lhs: URL, _ rhs: URL) -> Bool {
        let key: Set<URLResourceKey> = [.fileResourceIdentifierKey]
        guard
            let left = try? URL(fileURLWithPath: lhs.path).resourceValues(forKeys: key).fileResourceIdentifier,
            let right = try? URL(fileURLWithPath: rhs.path).resourceValues(forKeys: key).fileResourceIdentifier
        else { return false }
        return left.isEqual(right)
    }

    /// File > Rename…。名前を尋ねて同じフォルダ内で改名する。
    func renameFile() {
        guard let url = fileURL else { return }
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("rename_title", comment: "")
        alert.informativeText = NSLocalizedString("rename_message", comment: "")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = url.lastPathComponent
        alert.accessoryView = field
        alert.addButton(withTitle: NSLocalizedString("rename_button", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("cancel_button", comment: ""))
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            guard let newURL = Self.renamedURL(from: url, newName: field.stringValue) else {
                throw DocumentRelocationError.invalidName
            }
            try relocate(to: newURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// File > Move To…。フォルダを選んで同じ名前のまま移す。
    func moveFile() {
        guard let url = fileURL else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = url.deletingLastPathComponent()
        panel.prompt = NSLocalizedString("move_button", comment: "")
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        do {
            try relocate(to: Self.movedURL(from: url, toFolder: folder))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
