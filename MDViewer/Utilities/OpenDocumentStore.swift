import Foundation

/// 開いているドキュメントの一覧を保存し、次回起動時に復元するための記録。
/// ファイルはブックマークで保持するので、移動・改名されても追跡できる。
final class OpenDocumentStore {
    static let shared = OpenDocumentStore()

    private struct Entry {
        let data: Data
        let url: URL
    }

    private let defaults: UserDefaults
    private let listKey = "openDocumentBookmarks"
    /// 1件だけ記録していた旧バージョンのキー。一覧が空のときの引き継ぎ用。
    private let legacyKey = "lastOpenedBookmark"
    private var didClaimLaunchURLs = false
    /// 最後のウィンドウを閉じたとき、次回も開くために一覧へ残したファイル。
    /// その後ウェルカム画面から別のファイルを開いたら、閉じたファイルとして一覧から外す。
    private var keptAfterCloseKey: String?

    /// アプリ終了処理中は true。終了に伴うウィンドウ閉鎖で一覧が消えないようにするために使う。
    var isTerminating = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// ファイルを一覧に追加する。すでにあれば何もしない。
    func add(url: URL) {
        var entries = loadEntries()
        let target = DocumentWindowRegistry.key(for: url)
        var changed = false
        if let kept = keptAfterCloseKey {
            keptAfterCloseKey = nil
            if kept != target {
                entries.removeAll { DocumentWindowRegistry.key(for: $0.url) == kept }
                changed = true
            }
        }
        if !entries.contains(where: { DocumentWindowRegistry.key(for: $0.url) == target }),
           let data = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            entries.append(Entry(data: data, url: url))
            changed = true
        }
        if changed {
            saveEntries(entries)
        }
    }

    /// ウィンドウを閉じたファイルを一覧から外す。
    /// 他に復元できるファイルが無くなる場合は外さない（最後に閉じたファイルを次回も開くため）。
    func remove(url: URL) {
        guard !isTerminating else { return }
        let target = DocumentWindowRegistry.key(for: url)
        let entries = loadEntries()
        let remaining = entries.filter { DocumentWindowRegistry.key(for: $0.url) != target }
        guard remaining.contains(where: { FileManager.default.fileExists(atPath: $0.url.path) }) else {
            keptAfterCloseKey = target
            return
        }
        saveEntries(remaining)
    }

    /// 起動時に復元するファイルを返す。起動ごとに最初の1回だけ値を返し、以降は空。
    /// 存在しなくなったファイルは含めない。
    func claimLaunchURLs() -> [URL] {
        guard !didClaimLaunchURLs else { return [] }
        didClaimLaunchURLs = true
        return loadEntries().map(\.url).filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    // MARK: - Persistence

    private func loadEntries() -> [Entry] {
        var blobs = (defaults.array(forKey: listKey) as? [Data]) ?? []
        if blobs.isEmpty, let legacy = defaults.data(forKey: legacyKey), !legacy.isEmpty {
            blobs = [legacy]
        }
        return blobs.compactMap { data in
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: data,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else { return nil }
            return Entry(data: data, url: url)
        }
    }

    private func saveEntries(_ entries: [Entry]) {
        defaults.set(entries.map(\.data), forKey: listKey)
    }
}
