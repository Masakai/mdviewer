import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 直前に配置したドキュメントウィンドウ。続けて開くウィンドウをずらす基準にする。
    private weak var lastPlacedWindow: NSWindow?
    /// 一連のクローズでドキュメントを表示していたウィンドウがあったか。最後のウィンドウを閉じたときの判定に使う。
    private var closeTracker = DocumentCloseTracker()

    override init() {
        super.init()
        // SwiftUI は applicationDidFinishLaunching より先に最初のウィンドウを表示する。
        // 起動時の復元で送られる通知を取りこぼさないよう、生成時点で受信登録しておく。
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenLocalDocument(_:)),
            name: .openLocalDocument,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenNewDocumentWindow),
            name: .openNewDocumentWindow,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenDocumentInWindow(_:)),
            name: .openDocumentInWindow,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDocumentWindowWillClose(_:)),
            name: .documentWindowWillClose,
            object: nil
        )
    }

    func applicationDidFinishLaunching(_: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = true
    }

    func applicationWillTerminate(_: Notification) {
        // 終了に伴うウィンドウ閉鎖で、復元対象の一覧が消えないようにする
        OpenDocumentStore.shared.isTerminating = true
    }

    /// 最後の文書を閉じたあとにウェルカム画面を出すか。オフなら、ウィンドウを出さずに起動し続ける。既定はオン
    static let showsWelcomeAfterLastCloseKey = "showWelcomeAfterLastDocumentClosed"

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        let defaults = UserDefaults.standard
        let action = LastWindowClosedAction.decide(
            isTerminating: OpenDocumentStore.shared.isTerminating,
            closedDocument: closeTracker.consumeForLastWindowClosed(),
            // 起動引数（-showWelcomeAfterLastDocumentClosed NO など）では文字列で入るので、bool(forKey:) で読む
            showsWelcome: defaults.object(forKey: Self.showsWelcomeAfterLastCloseKey) == nil
                || defaults.bool(forKey: Self.showsWelcomeAfterLastCloseKey)
        )
        switch action {
        case .showWelcome:
            openWelcomeWindow()
            return false
        case .keepRunning:
            return false
        case .quit:
            return true
        }
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // ウィンドウが1つも無いときだけ新規ドキュメントを開く（最小化中のウィンドウは macOS が戻す）
        if !flag, !NSApp.windows.contains(where: \.isMiniaturized) {
            openNewDocumentWindow()
        }
        return true
    }

    func application(_: NSApplication, open urls: [URL]) {
        // 複数URLを同時に渡されても取りこぼさないよう、1URLにつき1つのウィンドウで開く（システム設定によってはタブになる）。
        // すでに開いているファイルは新しく開かず、既存のウィンドウを前面に出す。
        for url in urls {
            openOrActivateDocument(url: url)
        }
    }

    private func openOrActivateDocument(url: URL) {
        if let existing = DocumentWindowRegistry.shared.window(for: url) {
            if existing.isMiniaturized {
                existing.deminiaturize(nil)
            }
            existing.makeKeyAndOrderFront(nil)
            // 新しく読み込む場合（DocumentViewModel.load）と同じく、最近使った項目の先頭に移す。
            // AppDelegate は MainActor に隔離されていないが、ここは常にメインスレッドから呼ばれる
            MainActor.assumeIsolated {
                RecentDocuments.shared.note(url: url)
            }
        } else {
            openDocumentInNewWindow(url: url)
        }
    }

    @objc private func handleOpenDocumentInWindow(_ notification: Notification) {
        guard let url = notification.object as? URL else { return }
        openOrActivateDocument(url: url)
    }

    @objc private func handleOpenLocalDocument(_ notification: Notification) {
        // 文書内のリンクは、システム設定にかかわらず前面のドキュメントウィンドウのタブで開く。開いていれば前面に出す
        guard let url = notification.object as? URL else { return }
        if DocumentWindowRegistry.shared.window(for: url) != nil {
            openOrActivateDocument(url: url)
        } else {
            openDocumentInNewTab(url: url)
        }
    }

    @objc private func handleOpenNewDocumentWindow() {
        openNewDocumentWindow()
    }

    @objc private func handleDocumentWindowWillClose(_ notification: Notification) {
        closeTracker.windowWillClose(hadDocument: notification.userInfo?["hasDocument"] as? Bool ?? false)
        // タブグループをまとめて閉じると windowWillClose が続けて届く。それが一段落した時点で
        // ドキュメントウィンドウが残っていれば、記録を次のクローズに持ち越さない
        DispatchQueue.main.async { [weak self] in
            let windowsRemain = NSApp.windows.contains { window in
                DocumentWindowRegistry.shared.contains(window) && (window.isVisible || window.isMiniaturized)
            }
            self?.closeTracker.closingFinished(windowsRemain: windowsRemain)
        }
    }

    /// ウェルカム画面のウィンドウを開く。前回終了時のファイルは復元しない。
    private func openWelcomeWindow() {
        let window = makeDocumentWindow(rootView: ContentView(restoresLastOpened: false), title: "MDViewer")
        place(window)
        window.makeKeyAndOrderFront(nil)
    }

    /// 空の新規ドキュメントを新しいウィンドウで開く（システム設定によってはタブになる）。
    private func openNewDocumentWindow() {
        let window = makeDocumentWindow(rootView: ContentView(startsAsNewDocument: true), title: "Untitled")
        place(window)
        window.makeKeyAndOrderFront(nil)
    }

    /// 新しいドキュメントウィンドウを配置する。
    /// 最前面のドキュメントウィンドウから1段ずらし、ドキュメントウィンドウが無ければ画面中央に置く。
    private func place(_ window: NSWindow) {
        // 複数ファイルを続けて開くと、アプリが非アクティブな間はキーウィンドウが切り替わらない。
        // 前面に並べた順で判定し、直前に配置したウィンドウ（登録前の場合がある）も基準に含める。
        let reference = NSApp.orderedWindows.first { candidate in
            candidate !== window && candidate.isVisible
                && (candidate === lastPlacedWindow || DocumentWindowRegistry.shared.contains(candidate))
        }
        if let reference, let screen = reference.screen ?? NSScreen.main {
            let point = WindowPlacement.cascadedTopLeft(
                from: reference.frame,
                windowSize: window.frame.size,
                visibleFrame: screen.visibleFrame
            )
            window.setFrameTopLeftPoint(point)
        } else {
            window.center()
        }
        lastPlacedWindow = window
    }

    private func makeDocumentWindow(rootView: ContentView, title: String) -> NSWindow {
        let hosting = NSHostingController(rootView: rootView)
        // NSWindow(contentViewController:) で作ると、NavigationSplitView のサイドバー切り替えボタンが
        // ツールバーに出ない。先にウィンドウを作ってから載せる。
        // スタイルは WindowGroup が作るウィンドウ（.fullSizeContentView つき）と同じにして、タブにまとめても見た目をそろえる。
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hosting
        window.setContentSize(NSSize(width: 960, height: 700))
        window.minSize = NSSize(width: 800, height: 600)
        window.title = title
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .unified
        // タブにするかはシステム設定「書類を開くときはタブで」に任せる（tabbingMode は既定の .automatic）
        window.tabbingIdentifier = DocumentWindowRegistry.tabbingIdentifier
        return window
    }

    private func openDocumentInNewWindow(url: URL) {
        let window = makeDocumentWindow(rootView: ContentView(initialURL: url), title: url.lastPathComponent)
        // ContentView が描画されて登録するまでの間に同じURLが来ても重複しないよう、先に登録する
        DocumentWindowRegistry.shared.register(window: window, url: url)
        place(window)
        window.makeKeyAndOrderFront(nil)
    }

    /// 前面のドキュメントウィンドウにタブとして加える。ヘルプや設定のウィンドウは対象にせず、
    /// ドキュメントウィンドウが無ければ通常の新しいウィンドウで開く。
    private func openDocumentInNewTab(url: URL) {
        let front = NSApp.orderedWindows.first { candidate in
            candidate.isVisible && DocumentWindowRegistry.shared.contains(candidate)
        }
        guard let front else {
            openDocumentInNewWindow(url: url)
            return
        }
        let window = makeDocumentWindow(rootView: ContentView(initialURL: url), title: url.lastPathComponent)
        DocumentWindowRegistry.shared.register(window: window, url: url)
        front.addTabbedWindow(window, ordered: .above)
        window.makeKeyAndOrderFront(nil)
    }
}

/// 最後のウィンドウを閉じたときにウェルカム画面を出すか（ドキュメントを閉じた）、終了するか（ウェルカム画面を閉じた）を決める記録。
/// ドキュメントのタブとウェルカム画面のタブが混在するグループをまとめて閉じても閉じる順に左右されないよう、
/// 一連のクローズの間は「ドキュメントを表示していたか」を OR で保持する。
struct DocumentCloseTracker {
    private(set) var closedWindowHadDocument = false

    mutating func windowWillClose(hadDocument: Bool) {
        closedWindowHadDocument = closedWindowHadDocument || hadDocument
    }

    /// 一連のクローズが終わったときに呼ぶ。ウィンドウが残っていれば記録を消す。
    mutating func closingFinished(windowsRemain: Bool) {
        if windowsRemain {
            closedWindowHadDocument = false
        }
    }

    /// 最後のウィンドウを閉じたときに呼ぶ。ウェルカム画面を出すべきかを返し、記録を消す。
    mutating func consumeForLastWindowClosed() -> Bool {
        defer { closedWindowHadDocument = false }
        return closedWindowHadDocument
    }
}

/// 最後のウィンドウを閉じたあとにすること。
enum LastWindowClosedAction: Equatable {
    /// ウェルカム画面を開く（#13）
    case showWelcome
    /// ウィンドウを出さずに起動し続ける。ほかの Mac のアプリと同じ動き
    case keepRunning
    case quit

    /// - Parameters:
    ///   - isTerminating: ⌘Q などで終了処理中か。終了に伴うウィンドウ閉鎖では何も出さない
    ///   - closedDocument: 一連のクローズで文書のウィンドウを閉じたか（DocumentCloseTracker）
    ///   - showsWelcome: 最後の文書を閉じたあとにウェルカム画面を出す設定か
    static func decide(isTerminating: Bool, closedDocument: Bool, showsWelcome: Bool) -> Self {
        if isTerminating { return .quit }
        // ウェルカム画面を出さない設定では、ウェルカム画面を閉じたときも終了しない
        guard showsWelcome else { return .keepRunning }
        // ウェルカム画面そのものを閉じたときは、これまでどおり終了する
        return closedDocument ? .showWelcome : .quit
    }
}

extension Notification.Name {
    static let openNewDocumentWindow = Notification.Name("MDViewer.openNewDocumentWindow")
    /// object に URL を載せる。新しいウィンドウで開く（すでに開いていれば前面に出す）。
    static let openDocumentInWindow = Notification.Name("MDViewer.openDocumentInWindow")
    /// ドキュメントウィンドウが閉じる直前に送る。userInfo["hasDocument"] にドキュメントを表示していたかを載せる。
    static let documentWindowWillClose = Notification.Name("MDViewer.documentWindowWillClose")
}
