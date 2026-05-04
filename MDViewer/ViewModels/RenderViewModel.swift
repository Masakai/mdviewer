import SwiftUI
import Combine
import WebKit

@MainActor
final class RenderViewModel: ObservableObject {
    @Published var theme: MarkdownTheme = .githubLight
    @Published var fontSize: Double = 16
    @Published var hoveredURL: String = ""

    @AppStorage("selectedThemeId") private var storedThemeId: String = MarkdownTheme.githubLight.id
    @AppStorage("fontSize") private var storedFontSize: Double = 16
    @AppStorage("pdfPageSize") private var storedPDFPageSize: String = PDFPageSize.a4.rawValue

    weak var webView: WKWebView?

    private(set) var isRendererReady = false
    private var pendingMarkdown: String? = nil
    private var pendingBaseURL: URL? = nil
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

    func increaseFontSize() { setFontSize(fontSize + 2) }
    func decreaseFontSize() { setFontSize(fontSize - 2) }
    func resetFontSize()    { setFontSize(16) }

    func setBaseURL(_ directoryURL: URL) {
        guard isRendererReady else { pendingBaseURL = directoryURL; return }
        let urlString = directoryURL.absoluteString.replacingOccurrences(of: "'", with: "\\'")
        webView?.evaluateJavaScript("MDViewer.setBaseURL('\(urlString)')", completionHandler: nil)
    }

    func renderMarkdown(_ markdown: String) {
        guard isRendererReady else { pendingMarkdown = markdown; return }
        let escaped = escapeForJS(markdown)
        webView?.evaluateJavaScript("MDViewer.setContent('\(escaped)')", completionHandler: nil)
    }

    func rendererDidLoad() {
        isRendererReady = true
        applyCurrentThemeAndFontSize()
        applyPDFPageSize()
        if let url = pendingBaseURL {
            pendingBaseURL = nil
            let urlString = url.absoluteString.replacingOccurrences(of: "'", with: "\\'")
            webView?.evaluateJavaScript("MDViewer.setBaseURL('\(urlString)')", completionHandler: nil)
        }
        if let md = pendingMarkdown {
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
        if storedThemeId == MarkdownTheme.githubLight.id && isDark {
            setTheme(.githubDark)
        } else if storedThemeId == MarkdownTheme.githubDark.id && !isDark {
            setTheme(.githubLight)
        }
    }

    private func escapeForJS(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'",  with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "</", with: "<\\/")
    }
}
