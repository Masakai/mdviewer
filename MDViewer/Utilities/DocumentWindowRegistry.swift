import AppKit

/// 開いているドキュメントウィンドウと、そのウィンドウが表示しているファイルの対応表。
/// Finder や Dock から同じファイルを再度開かれたときに、既存のウィンドウを前面に出すために使う。
final class DocumentWindowRegistry {
    static let shared = DocumentWindowRegistry()

    private final class Entry {
        let urlProvider: () -> URL?
        init(urlProvider: @escaping () -> URL?) {
            self.urlProvider = urlProvider
        }
    }

    /// ウィンドウは弱参照で保持する（閉じたウィンドウは自動的に消える）。
    private let entries = NSMapTable<NSWindow, Entry>(keyOptions: .weakMemory, valueOptions: .strongMemory)

    /// ウィンドウが表示しているファイルを記録する。`url` が nil（ファイル無し）なら記録を消す。
    func register(window: NSWindow, url: URL?) {
        if url != nil {
            register(window: window) { url }
        } else {
            entries.removeObject(forKey: window)
        }
    }

    /// ウィンドウが表示しているファイルを、問い合わせのたびに `urlProvider` から取得する形で記録する。
    /// ウィンドウの中身が後から切り替わっても、常に最新のファイルで照合できる。
    func register(window: NSWindow, urlProvider: @escaping () -> URL?) {
        entries.setObject(Entry(urlProvider: urlProvider), forKey: window)
    }

    /// 指定ファイルを表示しているウィンドウを返す。無ければ nil。
    func window(for url: URL) -> NSWindow? {
        let target = Self.key(for: url)
        let enumerator = entries.keyEnumerator()
        while let window = enumerator.nextObject() as? NSWindow {
            if let current = entries.object(forKey: window)?.urlProvider(), Self.key(for: current) == target {
                return window
            }
        }
        return nil
    }

    /// シンボリックリンクや `..` の違いを吸収して同一ファイルを判定するためのキー。
    static func key(for url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}
