import AppKit
import Combine

/// 最近使った書類の記録先。本体は NSDocumentController で、テストでは偽物に差し替える。
@MainActor
protocol RecentDocumentControlling: AnyObject {
    var recentDocumentURLs: [URL] { get }
    func noteNewRecentDocumentURL(_ url: URL)
    func clearRecentDocuments(_ sender: Any?)
}

extension NSDocumentController: RecentDocumentControlling {}

/// File > Open Recent の一覧。
/// SwiftUI のメニューは NSDocumentController の変化を検知しないので、記録・消去のたびと、アプリが前面に来るたびに一覧を読み直して公開する。
@MainActor
final class RecentDocuments: ObservableObject {
    static let shared = RecentDocuments(controller: defaultController())

    @Published private(set) var urls: [URL] = []

    private let controller: RecentDocumentControlling
    private var didBecomeActiveObserver: AnyCancellable?

    init(controller: RecentDocumentControlling, notificationCenter: NotificationCenter = .default) {
        self.controller = controller
        urls = controller.recentDocumentURLs
        // このアプリの外で一覧が変わった場合（他のアプリからの消去など）にも追従する
        didBecomeActiveObserver = notificationCenter
            .publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.reload()
            }
    }

    func note(url: URL) {
        controller.noteNewRecentDocumentURL(url)
        urls = controller.recentDocumentURLs
    }

    func clear() {
        controller.clearRecentDocuments(nil)
        urls = controller.recentDocumentURLs
    }

    private func reload() {
        let latest = controller.recentDocumentURLs
        if latest != urls {
            urls = latest
        }
    }

    /// メニューに出す項目名。同じ名前のファイルが一覧に複数あるときだけ、見分けられるよう親フォルダ名を添える
    /// （例：`README.md — docs`）。
    nonisolated static func menuTitles(for urls: [URL]) -> [String] {
        var counts: [String: Int] = [:]
        for url in urls {
            counts[url.lastPathComponent, default: 0] += 1
        }
        return urls.map { url in
            let name = url.lastPathComponent
            guard counts[name, default: 0] > 1 else { return name }
            return "\(name) — \(url.deletingLastPathComponent().lastPathComponent)"
        }
    }

    /// テストのホストは本番アプリと同じバンドルIDで動くため、本物に書き込むとユーザーの
    /// 「最近使った項目」にテスト用の一時ファイルが残る。テスト実行中は何も記録しない。
    private static func defaultController() -> RecentDocumentControlling {
        let environment = ProcessInfo.processInfo.environment
        let isRunningTests = environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
            || NSClassFromString("XCTestCase") != nil
        return isRunningTests ? DiscardingRecentDocumentController() : NSDocumentController.shared
    }
}

/// 何も記録しない記録先。テスト実行中の既定値として使う。
private final class DiscardingRecentDocumentController: RecentDocumentControlling {
    var recentDocumentURLs: [URL] {
        []
    }

    func noteNewRecentDocumentURL(_: URL) {}
    func clearRecentDocuments(_: Any?) {}
}
