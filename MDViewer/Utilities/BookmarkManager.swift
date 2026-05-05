import Foundation

final class BookmarkManager {
    static let shared = BookmarkManager()

    private let userDefaults = UserDefaults.standard
    private let bookmarkKeyPrefix = "bookmark_"

    private init() {}

    func save(url: URL) {
        do {
            let data = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            userDefaults.set(data, forKey: bookmarkKeyPrefix + url.path)
        } catch {
            // Bookmark creation failed — fall back to direct path access
        }
    }

    func resolve(for path: String) -> URL? {
        guard let data = userDefaults.data(forKey: bookmarkKeyPrefix + path) else {
            return nil
        }

        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale {
                save(url: url)
            }
            return url
        } catch {
            return nil
        }
    }

    func startAccess(url: URL) -> Bool {
        url.startAccessingSecurityScopedResource()
    }

    func stopAccess(url: URL) {
        url.stopAccessingSecurityScopedResource()
    }
}
