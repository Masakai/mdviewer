import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 直前に配置したドキュメントウィンドウ。続けて開くウィンドウをずらす基準にする。
    private weak var lastPlacedWindow: NSWindow?
    /// 最後に閉じたウィンドウがドキュメントを表示していたか。ウェルカム画面を閉じたときは false。
    private var lastClosedWindowHadDocument = false

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

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        // 最後のドキュメントを閉じただけでは終了せず、ウェルカム画面を出す。ウェルカム画面を閉じたら終了する
        guard lastClosedWindowHadDocument, !OpenDocumentStore.shared.isTerminating else { return true }
        lastClosedWindowHadDocument = false
        openWelcomeWindow()
        return false
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
        lastClosedWindowHadDocument = notification.userInfo?["hasDocument"] as? Bool ?? false
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

extension Notification.Name {
    static let openNewDocumentWindow = Notification.Name("MDViewer.openNewDocumentWindow")
    /// object に URL を載せる。新しいウィンドウで開く（すでに開いていれば前面に出す）。
    static let openDocumentInWindow = Notification.Name("MDViewer.openDocumentInWindow")
    /// ドキュメントウィンドウが閉じる直前に送る。userInfo["hasDocument"] にドキュメントを表示していたかを載せる。
    static let documentWindowWillClose = Notification.Name("MDViewer.documentWindowWillClose")
}
