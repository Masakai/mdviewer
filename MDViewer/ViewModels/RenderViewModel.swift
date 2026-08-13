import Combine
import SwiftUI
import WebKit

@MainActor
final class RenderViewModel: ObservableObject {
    @Published var theme: MarkdownTheme = .githubLight
    @Published var fontSize: Double = 16
    @Published var hoveredURL: String = ""

    /// Set when the preview could not be recovered; nil while things are healthy.
    @Published var renderFailureMessage: String?

    @AppStorage("selectedThemeId") private var storedThemeId: String = MarkdownTheme.githubLight.id
    @AppStorage("fontSize") private var storedFontSize: Double = 16
    @AppStorage("pdfPageSize") private var storedPDFPageSize: String = PDFPageSize.a4.rawValue

    weak var webView: WKWebView?
    weak var schemeHandler: LocalSchemeHandler?

    private(set) var isRendererReady = false
    private var pendingMarkdown: String?
    private var pendingBaseURL: URL?

    /// The most recently rendered content, retained so it can be drawn again
    /// after reloading when recovering from a WebContent process crash.
    private var lastRenderedMarkdown: String?
    private var lastBaseURL: URL?

    /// Crash-loop guard: if the content itself crashes the WebContent process,
    /// re-rendering it on recovery would crash again indefinitely.
    private var consecutiveFailures = 0
    private var lastFailureTime: Date?
    private let maxConsecutiveFailures = 3
    private let failureWindow: TimeInterval = 10
    private var cancellables = Set<AnyCancellable>()

    init() {
        if let saved = MarkdownTheme.all.first(where: { $0.id == storedThemeId }) {
            theme = saved
        }
        fontSize = storedFontSize

        NotificationCenter.default
            .publisher(for: .pdfPageSizeChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyPDFPageSize() }
            .store(in: &cancellables)
    }

    func setTheme(_ newTheme: MarkdownTheme) {
        theme = newTheme
        storedThemeId = newTheme.id
        webView?.evaluateJavaScript("MDViewer.setTheme('\(newTheme.cssFileName)')", completionHandler: nil)
    }

    func setFontSize(_ size: Double) {
        let clamped = min(max(size, 10), 32)
        fontSize = clamped
        storedFontSize = clamped
        webView?.evaluateJavaScript("MDViewer.setFontSize(\(Int(clamped)))", completionHandler: nil)
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
        guard isRendererReady else { pendingMarkdown = markdown; return }
        let escaped = escapeForJS(markdown)
        webView?.evaluateJavaScript("MDViewer.setContent('\(escaped)')", completionHandler: nil)
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
            pendingMarkdown = nil
            renderFailureMessage = NSLocalizedString("preview_crash_loop_message", comment: "")
            return consecutiveFailures == maxConsecutiveFailures + 1
        }

        if pendingMarkdown == nil { pendingMarkdown = lastRenderedMarkdown }
        return true
    }

    /// Clears the crash-loop counter once a render has demonstrably succeeded.
    ///
    /// This runs after every render, so it must stay a no-op in the common case:
    /// assigning to a @Published property publishes even when the value is
    /// unchanged, which would invalidate the view on every keystroke.
    func noteRenderSucceeded() {
        guard consecutiveFailures != 0 || lastFailureTime != nil || renderFailureMessage != nil else {
            return
        }
        consecutiveFailures = 0
        lastFailureTime = nil
        renderFailureMessage = nil
    }

    func rendererDidLoad() {
        isRendererReady = true
        applyCurrentThemeAndFontSize()
        applyPDFPageSize()

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
        if let md = pendingMarkdown ?? lastRenderedMarkdown {
            pendingMarkdown = nil
            let escaped = escapeForJS(md)
            webView?.evaluateJavaScript("MDViewer.setContent('\(escaped)')", completionHandler: nil)
        }
    }

    func scrollToAnchor(_ anchor: String) {
        let escaped = anchor.replacingOccurrences(of: "'", with: "\\'")
        webView?.evaluateJavaScript("MDViewer.scrollToAnchor('\(escaped)')", completionHandler: nil)
    }

    var pdfPageSize: PDFPageSize {
        PDFPageSize(rawValue: storedPDFPageSize) ?? .a4
    }

    func setPDFPageSize(_ size: PDFPageSize) {
        storedPDFPageSize = size.rawValue
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
        webView?.evaluateJavaScript("MDViewer.setTheme('\(theme.cssFileName)')", completionHandler: nil)
        webView?.evaluateJavaScript("MDViewer.setFontSize(\(Int(fontSize)))", completionHandler: nil)
    }

    func applySystemAppearance(isDark: Bool) {
        if storedThemeId == MarkdownTheme.githubLight.id, isDark {
            setTheme(.githubDark)
        } else if storedThemeId == MarkdownTheme.githubDark.id, !isDark {
            setTheme(.githubLight)
        }
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
