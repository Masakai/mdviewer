import SwiftUI
import Combine

@MainActor
final class DocumentViewModel: ObservableObject {
    @Published var text: String = ""
    @Published var fileURL: URL?
    @Published var fileFormat: String = "markdown"
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    @AppStorage("lastOpenedBookmark") private var lastOpenedBookmarkData: Data = Data()

    private let fileWatcher = FileWatcher()
    private var activeSecurityScopedURL: URL?

    init() {
        fileWatcher.onChange = { [weak self] in
            Task { @MainActor in
                self?.reload()
            }
        }
    }

    var isAsciidoc: Bool {
        guard let ext = fileURL?.pathExtension.lowercased() else { return false }
        return ext == "adoc" || ext == "asciidoc" || ext == "asc"
    }

    func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.markdown, .asciidoc, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            load(url: url)
        }
    }

    func load(url: URL) {
        isLoading = true
        errorMessage = nil

        activeSecurityScopedURL?.stopAccessingSecurityScopedResource()
        let scopeOpened = url.startAccessingSecurityScopedResource()
        activeSecurityScopedURL = scopeOpened ? url : nil

        do {
            let contents = try String(contentsOf: url, encoding: .utf8)
            let ext = url.pathExtension.lowercased()
            self.fileURL = url
            self.fileFormat = (ext == "adoc" || ext == "asciidoc" || ext == "asc") ? "asciidoc" : "markdown"
            self.text = contents
            fileWatcher.start(url: url)
            BookmarkManager.shared.save(url: url)
            saveLastOpened(url: url)
        } catch {
            url.stopAccessingSecurityScopedResource()
            activeSecurityScopedURL = nil
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    deinit {
        activeSecurityScopedURL?.stopAccessingSecurityScopedResource()
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
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) {
            load(url: url)
        }
    }

    private func saveLastOpened(url: URL) {
        if let data = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            lastOpenedBookmarkData = data
        }
    }
}
