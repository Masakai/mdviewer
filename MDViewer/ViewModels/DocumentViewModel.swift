import SwiftUI
import Combine

@MainActor
final class DocumentViewModel: ObservableObject {
    @Published var text: String = ""
    @Published var fileURL: URL?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    @AppStorage("lastOpenedBookmark") private var lastOpenedBookmarkData: Data = Data()

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
            self.fileURL = url
            self.text = contents
            fileWatcher.start(url: url)
            BookmarkManager.shared.save(url: url)
            saveLastOpened(url: url)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func reload() {
        guard let url = fileURL else { return }
        do {
            let contents = try String(contentsOf: url, encoding: .utf8)
            self.text = contents
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
