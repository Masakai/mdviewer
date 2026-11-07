import Combine
import SwiftUI
import WebKit

@MainActor
final class RenderViewModel: ObservableObject {
    @Published var theme: MarkdownTheme = .githubLight
    /// Theme chosen from the toolbar and pinned to this window. While nil, Settings and the system appearance decide.
    @Published private(set) var windowThemeOverride: MarkdownTheme?
    @Published var fontSize: Double = 16
    @Published var hoveredURL: String = ""

    /// Set when the preview could not be recovered; nil while things are healthy.
    @Published var renderFailureMessage: String?

    /// Set when the crash-loop guard resets or halts the preview, cleared only
    /// once a render succeeds. Stored rather than derived from the guard's
    /// counters: those are zeroed while the preview is still empty — the page
    /// loading after a halt, a failure outside the window restarting the count —
    /// and dismissing the alert clears `renderFailureMessage`.
    @Published private(set) var isPreviewInterrupted = false

    /// 検索バーの一致件数。JS 側の検索（MDViewer.search）が数えて
    /// searchResultsChanged で知らせてくる。検索語を変えてから結果が届くまでは nil。
    @Published private(set) var searchStatus: SearchStatus?

    struct SearchStatus: Equatable {
        /// 何件目か（1始まり）。一致がなければ 0
        var current: Int
        var total: Int
    }

    /// 描画し直しは JS 側が同じ語で数え直すが、レンダラーを読み込み直したときは
    /// JS 側の状態が消えるので、ここで覚えておいて検索し直す。
    private(set) var searchQuery = ""
    /// 一致の位置までスクロールするか。エディタが検索の対象のときは、プレビューは強調だけにする。
    private(set) var searchScrolls = true

    /// 入力が止まるのを待っている検索
    private var pendingSearch: Task<Void, Never>?
    private(set) var pendingSearchQuery: String?

    /// テーマ・文字サイズ・PDF の用紙サイズ・数式の区切りの保存先。テストでは使い捨ての保存先を渡し、
    /// 利用者の設定（テストホストは本番と同じバンドルID）を書き換えないようにする。
    private let settings: UserDefaults
    private static let fontSizeKey = "fontSize"
    private static let pdfPageSizeKey = "pdfPageSize"
    /// \(...\) と \[...\] を数式として扱うか（#31）。既定はオフ
    static let mathBracketDelimitersKey = "mathBracketDelimiters"

    weak var webView: WKWebView?
    weak var schemeHandler: LocalSchemeHandler?

    private(set) var isRendererReady = false
    private var pendingMarkdown: String?
    private var pendingBaseURL: URL?

    /// The most recently rendered content, retained so it can be drawn again
    /// after reloading when recovering from a WebContent process crash.
    private var lastRenderedMarkdown: String?
    private var lastBaseURL: URL?

    /// Whether the content on screen holds a Mermaid diagram, as the page last
    /// reported it with renderComplete.
    private var displayedContentHasDiagrams = false
    /// Content was sent to the page and its renderComplete has not arrived yet,
    /// so displayedContentHasDiagrams may describe the previous content.
    private var isRenderInFlight = false

    /// Crash-loop guard: if the content itself crashes the WebContent process,
    /// re-rendering it on recovery would crash again indefinitely.
    private var consecutiveFailures = 0
    private var lastFailureTime: Date?
    private let maxConsecutiveFailures = 3
    private let failureWindow: TimeInterval = 10

    /// Set once the crash-loop guard has given up: the WebContent process is
    /// gone and nothing will load the renderer again on its own.
    private(set) var isRecoveryHalted = false

    /// Loads the renderer page again. Set by the view that owns the web view;
    /// returns false when there is no renderer on screen to reload.
    var reloadRenderer: (() -> Bool)?

    /// Called when the crash-loop guard resets the preview. Set by the view that
    /// owns the web view: what was extracted from the crashing content, such as
    /// the sidebar's headings, would otherwise outlive it, since the empty page
    /// that follows renders nothing to replace it.
    var onPreviewReset: (() -> Void)?
    private var cancellables = Set<AnyCancellable>()

    /// The system appearance as last seen.
    private var currentSystemIsDark: Bool

    /// - Parameters:
    ///   - systemIsDark: The system appearance; nil reads it from NSApp (tests pass a fixed value).
    ///   - systemAppearanceChanges: Where appearance changes come from; nil observes NSApp.
    init(
        settings: UserDefaults = .standard,
        systemIsDark: Bool? = nil,
        systemAppearanceChanges: AnyPublisher<Bool, Never>? = nil
    ) {
        self.settings = settings
        let isDark = systemIsDark ?? Self.readSystemIsDark()
        currentSystemIsDark = isDark
        theme = ThemePreference.load(from: settings).theme(systemIsDark: isDark)
        // 起動引数（-fontSize 20 など）では文字列で入るので、double(forKey:) で読む。
        // 数値として読めない値は 0 になり、文字が見えなくなるので既定の大きさにする
        if settings.object(forKey: Self.fontSizeKey) != nil {
            let saved = settings.double(forKey: Self.fontSizeKey)
            fontSize = saved > 0 ? Self.clampedFontSize(saved) : 16
        }

        NotificationCenter.default
            .publisher(for: .pdfPageSizeChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyPDFPageSize() }
            .store(in: &cancellables)

        // 設定画面でフォントを変えたら、開いているウィンドウにもすぐ反映する
        NotificationCenter.default
            .publisher(for: .previewFontsChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyFonts() }
            .store(in: &cancellables)

        // 設定画面で数式の区切りを切り替えたら、開いている文書を描画し直す
        NotificationCenter.default
            .publisher(for: .mathOptionsChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.mathOptionsDidChange() }
            .store(in: &cancellables)

        // 設定画面でテーマを選んだら、開いているウィンドウにもすぐ反映する
        NotificationCenter.default
            .publisher(for: .previewThemeChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applySettingsTheme() }
            .store(in: &cancellables)

        // When the system appearance changes, pick the theme again for windows that are not pinned.
        let appearanceChanges = systemAppearanceChanges ?? Self.systemAppearancePublisher()
        appearanceChanges
            .sink { [weak self] isDark in self?.applySystemAppearance(isDark: isDark) }
            .store(in: &cancellables)

        // 設定画面で文字サイズを変えたら、開いているウィンドウにもすぐ反映する。
        // 設定画面がすでに保存しているので、ここでは保存先に書かない
        NotificationCenter.default
            .publisher(for: .previewFontSizeChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let self, let size = notification.object as? Double else { return }
                let clamped = Self.clampedFontSize(size)
                guard clamped != self.fontSize else { return }
                self.applyFontSize(clamped)
            }
            .store(in: &cancellables)
    }

    /// このウィンドウのテーマだけを切り替える。設定（selectedThemeId）には書かない。
    /// ツールバーからの個別変更が全体設定や他のウィンドウに波及しないようにするため。
    /// From then on, Settings and appearance changes leave this window alone (useSettingsTheme() undoes it).
    func setTheme(_ newTheme: MarkdownTheme) {
        // Pin even when it is the theme already shown: set the pin before apply compares.
        windowThemeOverride = newTheme
        apply(newTheme)
    }

    /// Unpins the window and goes back to the theme Settings and the current appearance decide.
    func useSettingsTheme() {
        windowThemeOverride = nil
        applySettingsTheme()
    }

    /// Applies the theme Settings and the current appearance decide. Pinned windows are left alone.
    private func applySettingsTheme() {
        guard windowThemeOverride == nil else { return }
        apply(ThemePreference.load(from: settings).theme(systemIsDark: currentSystemIsDark))
    }

    /// The one place that updates theme and sends it to the page.
    private func apply(_ newTheme: MarkdownTheme) {
        guard newTheme != theme else { return }
        let oldTheme = theme
        theme = newTheme
        // Pages loaded later (a reload, crash recovery) also start in this theme.
        installInitialThemeScript()
        webView?.evaluateJavaScript(Self.setThemeScript(for: newTheme), completionHandler: nil)
        // Mermaid bakes the colours into its SVG when it draws, so redraw when light/dark changes.
        if Self.needsRerenderForThemeChange(
            from: oldTheme, to: newTheme,
            hasDiagrams: displayedContentHasDiagrams, isRenderInFlight: isRenderInFlight
        ), isRendererReady, let markdown = lastRenderedMarkdown {
            renderMarkdown(markdown)
        }
    }

    /// Redraws only when light/dark changes and a Mermaid diagram is on screen, or
    /// may be about to be: while a render is in flight the page has not said yet.
    static func needsRerenderForThemeChange(
        from old: MarkdownTheme, to new: MarkdownTheme, hasDiagrams: Bool, isRenderInFlight: Bool
    ) -> Bool {
        old.isDark != new.isDark && (hasDiagrams || isRenderInFlight)
    }

    /// Initial theme handed to mdviewer.js before the page loads: the stylesheet and background
    /// are decided before the first paint, so there is no white flash.
    static func initialThemeScriptSource(for theme: MarkdownTheme) -> String {
        "window.MDViewerInitialTheme = { css: '\(theme.cssFileName)', isDark: \(theme.isDark), background: '\(theme.backgroundHex)' };"
    }

    /// Replaces the initial-theme script with the current theme's, leaving no stale one behind.
    func installInitialThemeScript() {
        guard let controller = webView?.configuration.userContentController else { return }
        controller.removeAllUserScripts()
        controller.addUserScript(WKUserScript(
            source: Self.initialThemeScriptSource(for: theme),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
    }

    private static func readSystemIsDark() -> Bool {
        NSApp?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    private static func systemAppearancePublisher() -> AnyPublisher<Bool, Never> {
        guard let app = NSApp else { return Empty<Bool, Never>().eraseToAnyPublisher() }
        return app.publisher(for: \.effectiveAppearance)
            .map { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .eraseToAnyPublisher()
    }

    /// テーマを切り替える JS。ダークかどうかはテーマ名から判別できないので、明示的に渡す。
    static func setThemeScript(for theme: MarkdownTheme) -> String {
        "MDViewer.setTheme('\(theme.cssFileName)', \(theme.isDark))"
    }

    func setFontSize(_ size: Double) {
        let clamped = Self.clampedFontSize(size)
        settings.set(clamped, forKey: Self.fontSizeKey)
        applyFontSize(clamped)
    }

    private static func clampedFontSize(_ size: Double) -> Double {
        min(max(size, 10), 32)
    }

    private func applyFontSize(_ size: Double) {
        fontSize = size
        webView?.evaluateJavaScript("MDViewer.setFontSize(\(Int(size)))", completionHandler: nil)
    }

    func increaseFontSize() {
        setFontSize(fontSize + 2)
    }

    func decreaseFontSize() {
        setFontSize(fontSize - 2)
    }

    func resetFontSize() {
        setFontSize(16)
    }

    func setBaseURL(_ directoryURL: URL) {
        // The Markdown file's directory is served to the WebView through the
        // custom mdviewer-local:// scheme handler, which enforces path security.
        schemeHandler?.baseDirectory = directoryURL.standardizedFileURL
        lastBaseURL = directoryURL
        guard isRendererReady else { pendingBaseURL = directoryURL; return }
        applyBaseURL()
    }

    private func applyBaseURL() {
        // Relative resource URLs in the rendered HTML resolve against this base,
        // so `image.png` becomes `mdviewer-local://localhost/image.png`.
        webView?.evaluateJavaScript("MDViewer.setBaseURL('mdviewer-local://localhost/')", completionHandler: nil)
    }

    func renderMarkdown(_ markdown: String) {
        lastRenderedMarkdown = markdown
        guard isRendererReady else {
            pendingMarkdown = markdown
            retryHaltedRenderer()
            return
        }
        let escaped = escapeForJS(markdown)
        webView?.evaluateJavaScript("MDViewer.setContent('\(escaped)')", completionHandler: nil)
        isRenderInFlight = true
    }

    /// Once the guard has given up, new content — an edit, reloading the file,
    /// reopening it — is the user trying again: the renderer gets a fresh
    /// budget and is reloaded, and rendererDidLoad() draws the queued content.
    /// If it keeps crashing the guard stops it again after the same number of
    /// attempts. Edits made before the reload finishes only update the queued
    /// content, since the renderer is not ready until then.
    private func retryHaltedRenderer() {
        guard isRecoveryHalted, reloadRenderer?() == true else { return }
        resumeRecovery()
    }

    /// Leaves the halted state with a fresh budget, so the next crash is
    /// recovered from rather than counted against the budget used up before.
    private func resumeRecovery() {
        isRecoveryHalted = false
        consecutiveFailures = 0
        lastFailureTime = nil
    }

    /// Called when the WebContent process terminates or a navigation fails.
    ///
    /// Unless `isRendererReady` is reset to false, subsequent `renderMarkdown`
    /// calls pass the guard and keep running evaluateJavaScript against a dead
    /// page, failing silently and leaving the preview permanently white. The
    /// current content is moved back to pending so it is re-rendered once the
    /// reload completes.
    ///
    /// - Returns: whether the caller should reload the renderer. False once the
    ///   crashes look self-inflicted — if the content itself is what kills the
    ///   WebContent process, re-rendering it would crash again in a loop.
    ///
    /// - Parameter now: the current time, injectable so the crash-loop window can
    ///   be exercised in tests without waiting in real time.
    @discardableResult
    func rendererDidFail(now: Date = Date()) -> Bool {
        isRendererReady = false
        if pendingBaseURL == nil { pendingBaseURL = lastBaseURL }

        if let last = lastFailureTime, now.timeIntervalSince(last) < failureWindow {
            consecutiveFailures += 1
        } else {
            consecutiveFailures = 1
        }
        lastFailureTime = now

        guard consecutiveFailures <= maxConsecutiveFailures else {
            // Reload once more but without the content that keeps crashing, so
            // the user gets a usable empty renderer instead of a crash loop.
            // Both copies must go: rendererDidLoad() falls back to the last
            // render, which would draw the crashing content straight back.
            pendingMarkdown = nil
            lastRenderedMarkdown = nil
            renderFailureMessage = NSLocalizedString("preview_crash_loop_message", comment: "")
            if !isPreviewInterrupted {
                isPreviewInterrupted = true
            }
            onPreviewReset?()
            let reloadsOnceMore = consecutiveFailures == maxConsecutiveFailures + 1
            if !reloadsOnceMore {
                isRecoveryHalted = true
            }
            return reloadsOnceMore
        }

        if pendingMarkdown == nil { pendingMarkdown = lastRenderedMarkdown }
        return true
    }

    /// Clears the crash-loop counter once a render has demonstrably succeeded,
    /// and records whether a Mermaid diagram is now on screen.
    ///
    /// This runs after every render, so it must stay a no-op in the common case:
    /// assigning to a @Published property publishes even when the value is
    /// unchanged, which would invalidate the view on every keystroke.
    ///
    /// - Parameter hasDiagrams: whether the page now shows a Mermaid diagram.
    func noteRenderSucceeded(hasDiagrams: Bool = false) {
        isRenderInFlight = false
        displayedContentHasDiagrams = hasDiagrams
        guard consecutiveFailures != 0 || lastFailureTime != nil || renderFailureMessage != nil
            || isPreviewInterrupted
        else {
            return
        }
        consecutiveFailures = 0
        lastFailureTime = nil
        renderFailureMessage = nil
        isPreviewInterrupted = false
    }

    /// Try Again on an interrupted preview, with the text currently in memory.
    ///
    /// After a reset the renderer is alive (or its empty reload is in flight),
    /// so the content gets a fresh budget and is drawn, or queued for
    /// rendererDidLoad(). Once halted, the fresh budget must wait:
    /// renderMarkdown() only reloads a halted renderer, and resets the budget
    /// itself when the reload starts. Nothing is cleared here — the banner and
    /// the alert go when a render succeeds. Outside an interruption it does
    /// nothing. While the banner is up, pressing it again during a retried
    /// crash-loop does hand the budget back, so each press costs at most
    /// `maxConsecutiveFailures` more crashes before the guard steps in again.
    func retryRendering(_ markdown: String) {
        guard isPreviewInterrupted else { return }
        if !isRecoveryHalted { resumeRecovery() }
        renderMarkdown(markdown)
    }

    /// What `rendererDidLoad()` draws once the page has loaded: anything queued
    /// while the renderer was not ready, otherwise the last content, so a native
    /// Reload does not come back blank. Nil once the crash-loop guard has reset
    /// the preview.
    var markdownToRestore: String? {
        pendingMarkdown ?? lastRenderedMarkdown
    }

    func rendererDidLoad() {
        isRendererReady = true
        // A fresh page shows nothing yet.
        displayedContentHasDiagrams = false
        isRenderInFlight = false
        if isRecoveryHalted {
            resumeRecovery()
        }
        applyCurrentThemeAndFontSize()
        applyPDFPageSize()
        // 区切りの判定は setContent の中で行うので、内容より先に渡す
        applyMathOptions()

        // Fall back to the base URL of the last render: the renderer can be
        // reloaded without anything pending — the context menu offers a native
        // Reload — and the freshly loaded page knows nothing about it.
        if pendingBaseURL != nil || lastBaseURL != nil {
            pendingBaseURL = nil
            applyBaseURL()
        }

        // Same for the content itself. Without the fallback a native reload
        // repaints an empty document, leaving the preview blank with no way
        // back until the file is reopened.
        if let md = markdownToRestore {
            pendingMarkdown = nil
            let escaped = escapeForJS(md)
            webView?.evaluateJavaScript("MDViewer.setContent('\(escaped)')", completionHandler: nil)
            isRenderInFlight = true
        }

        // 入力が止まるのを待っている語があれば、そちらで検索する。確定済みの古い語で
        // 検索すると、待っている検索が取り消されてしまう。
        let query = pendingSearchQuery ?? searchQuery
        if !query.isEmpty {
            search(query, scroll: searchScrolls)
        }
    }

    // MARK: - 検索

    /// 検索欄への入力。1文字ごとに全文を走査しないよう、入力が止まってから検索する。
    /// 空にしたときはすぐにハイライトを消す。
    func searchAsTyped(_ query: String, scroll: Bool = true, delay: Duration = .milliseconds(150)) {
        guard !query.isEmpty else {
            search(query, scroll: scroll)
            return
        }
        pendingSearch?.cancel()
        pendingSearchQuery = query
        searchScrolls = scroll
        pendingSearch = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.search(query, scroll: scroll)
        }
    }

    /// 入力待ちの検索があれば、待たずに今すぐ検索する。
    /// - Returns: 検索したかどうか
    private func flushPendingSearch() -> Bool {
        guard let query = pendingSearchQuery else { return false }
        search(query, scroll: searchScrolls)
        return true
    }

    private func cancelPendingSearch() {
        pendingSearch?.cancel()
        pendingSearch = nil
        pendingSearchQuery = nil
    }

    /// - Parameter scroll: false なら一致を強調するだけで、読んでいる位置は動かさない。
    func search(_ query: String, scroll: Bool = true) {
        cancelPendingSearch()
        searchQuery = query
        searchScrolls = scroll
        guard !query.isEmpty else {
            clearSearch()
            return
        }
        searchStatus = nil
        guard isRendererReady else { return }
        webView?.callAsyncJavaScript(
            "MDViewer.search(query, scroll);",
            arguments: ["query": query, "scroll": scroll],
            in: nil,
            in: .page,
            completionHandler: nil
        )
    }

    /// 入力の直後に押されたときは、まだ検索していない語で最初の一致へ移る。
    func findNext() {
        guard !flushPendingSearch(), isRendererReady, !searchQuery.isEmpty else { return }
        webView?.evaluateJavaScript("MDViewer.searchNext();", completionHandler: nil)
    }

    func findPrevious() {
        guard !flushPendingSearch(), isRendererReady, !searchQuery.isEmpty else { return }
        webView?.evaluateJavaScript("MDViewer.searchPrevious();", completionHandler: nil)
    }

    func clearSearch() {
        cancelPendingSearch()
        searchQuery = ""
        searchStatus = nil
        guard isRendererReady else { return }
        webView?.evaluateJavaScript("MDViewer.clearSearch();", completionHandler: nil)
    }

    func searchResultsChanged(current: Int, total: Int) {
        // 検索を閉じた後に届いた結果で、件数を出し直さない
        guard !searchQuery.isEmpty else { return }
        searchStatus = SearchStatus(current: current, total: total)
    }

    func scrollToAnchor(_ anchor: String) {
        let escaped = anchor.replacingOccurrences(of: "'", with: "\\'")
        webView?.evaluateJavaScript("MDViewer.scrollToAnchor('\(escaped)')", completionHandler: nil)
    }

    var pdfPageSize: PDFPageSize {
        settings.string(forKey: Self.pdfPageSizeKey).flatMap(PDFPageSize.init(rawValue:)) ?? .a4
    }

    func setPDFPageSize(_ size: PDFPageSize) {
        settings.set(size.rawValue, forKey: Self.pdfPageSizeKey)
        applyPDFPageSize(size)
    }

    func applyPDFPageSize(_ size: PDFPageSize? = nil) {
        let s = size ?? pdfPageSize
        let css = "@page { size: \(s.cssSize); margin: 15mm; }"
        let js = """
        (function() {
            var el = document.getElementById('mdviewer-page-style');
            if (!el) { el = document.createElement('style'); el.id = 'mdviewer-page-style'; document.head.appendChild(el); }
            el.textContent = '\(css)';
        })();
        """
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    func applyCurrentThemeAndFontSize() {
        webView?.evaluateJavaScript(Self.setThemeScript(for: theme), completionHandler: nil)
        webView?.evaluateJavaScript("MDViewer.setFontSize(\(Int(fontSize)))", completionHandler: nil)
        applyFonts()
    }

    func applyFonts() {
        webView?.evaluateJavaScript(PreviewFont.setFontsScript(), completionHandler: nil)
    }

    var mathBracketDelimiters: Bool {
        settings.bool(forKey: Self.mathBracketDelimitersKey)
    }

    static func setMathOptionsScript(bracketDelimiters: Bool) -> String {
        "MDViewer.setMathOptions({ bracketDelimiters: \(bracketDelimiters) })"
    }

    func applyMathOptions() {
        webView?.evaluateJavaScript(
            Self.setMathOptionsScript(bracketDelimiters: mathBracketDelimiters),
            completionHandler: nil
        )
    }

    /// 区切りは描画のときにしか効かないので、表示中の内容を描画し直す。
    /// レンダラーの準備ができていなければ、rendererDidLoad() が設定を渡してから描画する。
    private func mathOptionsDidChange() {
        guard isRendererReady else { return }
        applyMathOptions()
        if let markdown = lastRenderedMarkdown {
            renderMarkdown(markdown)
        }
    }

    /// Remembers the system appearance and picks the theme again for windows that are not pinned.
    func applySystemAppearance(isDark: Bool) {
        currentSystemIsDark = isDark
        applySettingsTheme()
    }

    private func escapeForJS(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "</", with: "<\\/")
    }
}
