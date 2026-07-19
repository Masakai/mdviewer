import Combine
import SwiftUI

@MainActor
final class DocumentViewModel: ObservableObject {
    @Published var text: String = ""
    @Published var fileURL: URL?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var isDirty: Bool = false
    @Published var hasDocument: Bool = false

    @AppStorage("lastOpenedBookmark") private var lastOpenedBookmarkData: Data = .init()

    private let fileWatcher = FileWatcher()

    init() {
        fileWatcher.onChange = { [weak self] in
            Task { @MainActor in
                self?.reload()
            }
        }
    }

    func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.markdown, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
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

    func restoreLastOpened() {
        guard !lastOpenedBookmarkData.isEmpty else { return }
        var isStale = false
        if let url = try? URL(
            resolvingBookmarkData: lastOpenedBookmarkData,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) {
            load(url: url)
        }
    }

    private func saveLastOpened(url: URL) {
        if let data = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            lastOpenedBookmarkData = data
        }
    }
}
