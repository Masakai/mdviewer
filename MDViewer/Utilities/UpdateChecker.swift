import AppKit

/// ヘルプ > アップデートを確認… の処理。GitHub の最新リリースの版番号を取得して、使っている版と比べる。
/// アプリの入れ替えはせず、新しい版があればリリースページを開けるようにするだけ。
/// 問い合わせるのはメニューを選んだときだけで、起動時などに自動では通信しない。
@MainActor
final class UpdateChecker {
    static let shared = UpdateChecker()

    struct Release: Equatable {
        /// 先頭の v を除いた版番号（"1.10.0"）
        let version: String
        let pageURL: URL
    }

    enum Outcome: Equatable {
        case updateAvailable(Release)
        case upToDate
        case failed
    }

    typealias Loader = (URLRequest) async throws -> (Data, URLResponse)

    static let latestReleaseAPI = URL(string: "https://api.github.com/repos/Masakai/mdviewer/releases/latest")!
    static let releasesPage = URL(string: "https://github.com/Masakai/mdviewer/releases")!

    private let load: Loader
    private var isChecking = false

    init(load: @escaping Loader = { try await URLSession.shared.data(for: $0) }) {
        self.load = load
    }

    // MARK: - 判定

    /// releases/latest の JSON から版番号とページを取り出す。下書きとプレリリースは GitHub が返さない。
    nonisolated static func parseRelease(_ data: Data) -> Release? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = object["tag_name"] as? String,
              let page = (object["html_url"] as? String).flatMap(URL.init(string:)),
              versionComponents(tag) != nil
        else { return nil }
        return Release(version: normalized(tag), pageURL: page)
    }

    /// 版番号を数値として比べる。文字列で比べると 1.10.0 が 1.9.0 より古く見える。
    /// 数値として読めない版番号は、新しいとはみなさない。
    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard var lhs = versionComponents(candidate), var rhs = versionComponents(current) else { return false }
        let count = max(lhs.count, rhs.count)
        lhs += Array(repeating: 0, count: count - lhs.count)
        rhs += Array(repeating: 0, count: count - rhs.count)
        return rhs.lexicographicallyPrecedes(lhs)
    }

    nonisolated static func outcome(latest: Release?, currentVersion: String) -> Outcome {
        guard let latest else { return .failed }
        return isNewer(latest.version, than: currentVersion) ? .updateAvailable(latest) : .upToDate
    }

    private nonisolated static func normalized(_ version: String) -> String {
        version.hasPrefix("v") || version.hasPrefix("V") ? String(version.dropFirst()) : version
    }

    private nonisolated static func versionComponents(_ version: String) -> [Int]? {
        let parts = normalized(version).split(separator: ".", omittingEmptySubsequences: false)
        let numbers = parts.compactMap { Int($0) }
        guard !parts.isEmpty, numbers.count == parts.count, numbers.allSatisfy({ $0 >= 0 }) else { return nil }
        return numbers
    }

    // MARK: - 問い合わせ

    /// 最新リリースを取得する。通信できない・200 以外・JSON が読めないときは nil。
    func fetchLatestRelease() async -> Release? {
        var request = URLRequest(url: Self.latestReleaseAPI, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await load(request),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return Self.parseRelease(data)
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    // MARK: - 表示

    /// メニューから呼ぶ。結果をアラートで知らせる。確認中にもう一度選ばれても、問い合わせは1回にする。
    func checkForUpdates() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        let current = Self.currentVersion
        let outcome = await Self.outcome(latest: fetchLatestRelease(), currentVersion: current)
        present(outcome, currentVersion: current)
    }

    private func present(_ outcome: Outcome, currentVersion: String) {
        let alert = NSAlert()
        var pageToOpen: URL?
        switch outcome {
        case let .updateAvailable(release):
            alert.messageText = String(
                format: NSLocalizedString("update_available_title", comment: ""),
                release.version
            )
            alert.informativeText = String(
                format: NSLocalizedString("update_available_message", comment: ""), currentVersion
            )
            alert.addButton(withTitle: NSLocalizedString("update_open_release_page_button", comment: ""))
            alert.addButton(withTitle: NSLocalizedString("update_later_button", comment: ""))
            pageToOpen = release.pageURL
        case .upToDate:
            alert.messageText = NSLocalizedString("up_to_date_title", comment: "")
            alert.informativeText = String(format: NSLocalizedString("up_to_date_message", comment: ""), currentVersion)
            alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
        case .failed:
            // 確認できなくても、これまでどおりリリースページを開いて自分で確かめられるようにする
            alert.messageText = NSLocalizedString("update_check_failed_title", comment: "")
            alert.informativeText = NSLocalizedString("update_check_failed_message", comment: "")
            alert.alertStyle = .warning
            alert.addButton(withTitle: NSLocalizedString("update_open_release_page_button", comment: ""))
            alert.addButton(withTitle: NSLocalizedString("cancel_button", comment: ""))
            pageToOpen = Self.releasesPage
        }

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn, let pageToOpen {
            NSWorkspace.shared.open(pageToOpen)
        }
    }
}
