import SwiftUI
import WebKit

extension Notification.Name {
    static let openLocalDocument = Notification.Name("MDViewer.openLocalDocument")
}

struct WebRendererView: NSViewRepresentable {
    @ObservedObject var renderVM: RenderViewModel
    @ObservedObject var sidebarVM: SidebarViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(renderVM: renderVM, sidebarVM: sidebarVM)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()

        // Register JS message handlers
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "headingsExtracted")
        contentController.add(context.coordinator, name: "renderComplete")
        contentController.add(context.coordinator, name: "renderFailed")
        contentController.add(context.coordinator, name: "scrollPositionChanged")
        contentController.add(context.coordinator, name: "linkHovered")
        contentController.add(context.coordinator, name: "linkClicked")
        contentController.add(context.coordinator, name: "searchResultsChanged")
        config.userContentController = contentController

        // Register custom scheme for local images
        config.setURLSchemeHandler(context.coordinator.schemeHandler, forURLScheme: "mdviewer-local")

        let webView = RendererWebView(frame: .zero, configuration: config)
        webView.allowsLinkPreview = false
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator

        context.coordinator.webView = webView
        renderVM.webView = webView
        // Install it before loading, so the first paint already uses the theme's colours.
        renderVM.installInitialThemeScript()
        renderVM.schemeHandler = context.coordinator.schemeHandler
        renderVM.reloadRenderer = { [weak coordinator = context.coordinator] in
            guard let webView = coordinator?.webView else { return false }
            return Coordinator.loadRenderer(into: webView)
        }
        // After a reset the text is unchanged and the empty page renders
        // nothing, so no headingsExtracted would replace the crashed content's.
        renderVM.onPreviewReset = { [weak coordinator = context.coordinator] in
            coordinator?.sidebarVM.tocItems = []
        }

        loadRenderer(webView: webView)

        return webView
    }

    func updateNSView(_: WKWebView, context _: Context) {
        // Content updates are driven by RenderViewModel, not SwiftUI updates
    }

    private func loadRenderer(webView: WKWebView) {
        Coordinator.loadRenderer(into: webView)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
        let renderVM: RenderViewModel
        let sidebarVM: SidebarViewModel
        let schemeHandler = LocalSchemeHandler()
        weak var webView: WKWebView?

        init(renderVM: RenderViewModel, sidebarVM: SidebarViewModel) {
            self.renderVM = renderVM
            self.sidebarVM = sidebarVM
        }

        /// Called when the renderer HTML finishes loading — push initial content
        func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "headingsExtracted":
                handleHeadingsExtracted(message.body)
            case "renderComplete":
                handleRenderComplete(message.body)
            case "renderFailed":
                let reason = message.body as? String ?? "unknown"
                NSLog("MDViewer: render failed in WebView: %@", reason)
            case "scrollPositionChanged":
                break
            case "linkHovered":
                let href = message.body as? String ?? ""
                let url = href.hasPrefix("#")
                    ? nil
                    : Self.resolveLinkURL(href, relativeTo: schemeHandler.baseDirectory)
                let display = url.map { $0.isFileURL ? $0.path : $0.absoluteString } ?? href
                Task { @MainActor in self.renderVM.hoveredURL = display }
            case "linkClicked":
                guard let href = message.body as? String,
                      let url = Self.resolveLinkURL(href, relativeTo: schemeHandler.baseDirectory)
                else { break }
                Task { @MainActor in
                    if url.scheme == "file",
                       ["md", "markdown"].contains(url.pathExtension.lowercased())
                    {
                        NotificationCenter.default.post(name: .openLocalDocument, object: url)
                    } else if Self.isOpenableLinkURL(url) {
                        NSWorkspace.shared.open(url)
                    }
                }
            case "searchResultsChanged":
                guard let status = message.body as? [String: Any],
                      let current = status["current"] as? Int,
                      let total = status["total"] as? Int
                else { break }
                Task { @MainActor in self.renderVM.searchResultsChanged(current: current, total: total) }
            default:
                break
            }
        }

        /// Resolves a link's raw href against the directory of the open Markdown
        /// file. The page itself is renderer.html inside the app bundle, so the
        /// WebView's own resolution would point relative links into the bundle.
        ///
        /// - Returns: nil for a relative href when no file is open, since there
        ///   is nothing to resolve it against.
        /// Schemes a link in the preview may hand to `NSWorkspace`. linkClicked
        /// can be posted by any script on the page, so anything else — app URL
        /// schemes included — is not opened.
        static func isOpenableLinkURL(_ url: URL) -> Bool {
            guard let scheme = url.scheme?.lowercased() else { return false }
            return ["http", "https", "mailto", "file"].contains(scheme)
        }

        static func resolveLinkURL(_ href: String, relativeTo directory: URL?) -> URL? {
            if let url = URL(string: href), url.scheme != nil {
                return url
            }
            guard let directory else { return nil }
            let base = directory.hasDirectoryPath
                ? directory
                : URL(fileURLWithPath: directory.path, isDirectory: true)
            guard let url = URL(string: href, relativeTo: base)?.absoluteURL else { return nil }
            return url.isFileURL ? url.standardizedFileURL : url
        }

        private func handleHeadingsExtracted(_ body: Any) {
            guard let array = body as? [[String: Any]] else { return }
            var items: [TOCItem] = []
            for dict in array {
                guard
                    let level = dict["level"] as? Int,
                    let title = dict["title"] as? String,
                    let anchor = dict["anchor"] as? String
                else { continue }
                items.append(TOCItem(level: level, title: title, anchor: anchor))
            }
            Task { @MainActor in
                self.sidebarVM.tocItems = items
            }
        }

        /// A completed render is the proof that the renderer is healthy, so it
        /// clears the crash-loop guard.
        private func handleRenderComplete(_ body: Any) {
            let hasDiagrams = (body as? [String: Any])?["hasDiagrams"] as? Bool ?? false
            Task { @MainActor in self.renderVM.noteRenderSucceeded(hasDiagrams: hasDiagrams) }
        }

        // MARK: - Renderer loading / recovery

        /// Loads renderer.html, both for the initial display and when recovering
        /// from a WebContent process crash.
        ///
        /// - Returns: whether a load was started; false if the renderer's
        ///   resources are missing from the bundle.
        @discardableResult
        static func loadRenderer(into webView: WKWebView) -> Bool {
            guard let rendererURL = HTMLBuilder.rendererURL(),
                  let resourcesDir = HTMLBuilder.webResourcesDirectory()
            else { return false }

            webView.loadFileURL(rendererURL, allowingReadAccessTo: resourcesDir)
            return true
        }

        /// Recovers by reloading the renderer.
        ///
        /// Once the reload completes, `didFinish` calls `rendererDidLoad()`,
        /// which automatically re-renders the content held in pending.
        @MainActor
        private func recoverRenderer() {
            guard renderVM.rendererDidFail(), let webView else { return }
            Self.loadRenderer(into: webView)
        }

        /// Called when the WebContent process terminates.
        ///
        /// In that state the WKWebView renders as a blank white area with only
        /// the SwiftUI sidebar left visible. Without reloading here, every
        /// subsequent evaluateJavaScript call fails silently and the preview
        /// never recovers until the app is restarted.
        func webViewWebContentProcessDidTerminate(_: WKWebView) {
            Task { @MainActor in self.recoverRenderer() }
        }

        func webView(_: WKWebView, didFail _: WKNavigation!, withError error: any Error) {
            handleNavigationFailure(error)
        }

        func webView(
            _: WKWebView,
            didFailProvisionalNavigation _: WKNavigation!,
            withError error: any Error
        ) {
            handleNavigationFailure(error)
        }

        /// A failed load leaves the renderer as unusable as a crash does, so it
        /// is recovered the same way. Marking it failed without reloading would
        /// queue every later render with nothing left to flush it.
        private func handleNavigationFailure(_ error: any Error) {
            guard !Self.isSupersededNavigation(error) else { return }
            Task { @MainActor in self.recoverRenderer() }
        }

        /// A navigation cancelled because a newer one replaced it. That is not a
        /// renderer failure — the newer navigation reports its own outcome — and
        /// recovering from it would count against the crash-loop guard and
        /// replace the navigation that superseded it.
        static func isSupersededNavigation(_ error: any Error) -> Bool {
            (error as? URLError)?.code == .cancelled
        }

        // MARK: - WKUIDelegate

        func webView(
            _: WKWebView,
            createWebViewWith _: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures _: WKWindowFeatures
        ) -> WKWebView? {
            guard let url = navigationAction.request.url else { return nil }
            Task { @MainActor in
                if url.scheme == "file", ["md", "markdown"].contains(url.pathExtension.lowercased()) {
                    NotificationCenter.default.post(name: .openLocalDocument, object: url)
                } else if let scheme = url.scheme, ["http", "https", "mailto"].contains(scheme) {
                    NSWorkspace.shared.open(url)
                }
            }
            return nil
        }

        // MARK: - WKNavigationDelegate

        func webView(_: WKWebView, didFinish _: WKNavigation!) {
            Task { @MainActor in
                self.renderVM.rendererDidLoad()
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.navigationType == .linkActivated,
                  let url = navigationAction.request.url
            else {
                decisionHandler(.allow)
                return
            }

            // Fragment-only navigation stays in-page
            if url.fragment != nil,
               url.scheme == webView.url?.scheme,
               url.host == webView.url?.host
            {
                decisionHandler(.allow)
                return
            }

            // Local Markdown file → open in MDViewer
            if url.scheme == "file",
               ["md", "markdown"].contains(url.pathExtension.lowercased())
            {
                NotificationCenter.default.post(name: .openLocalDocument, object: url)
                decisionHandler(.cancel)
                return
            }

            // http / https / mailto → open in default app
            if let scheme = url.scheme,
               ["http", "https", "mailto"].contains(scheme)
            {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }

            // Any other link would navigate the renderer itself away
            decisionHandler(.cancel)
        }
    }
}

/// With the editor hidden, the preview is the only child of an HSplitView, and
/// HSplitView lays it out at a stale width and zero height on every live-resize
/// step before the real frame. The web view would paint that empty viewport as
/// a white flash; such frames are never meaningful for the preview, so ignore them.
final class RendererWebView: WKWebView {
    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        // Show the SwiftUI background (the theme's colour) until the page has painted.
        setValue(false, forKey: "drawsBackground")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func setFrameSize(_ newSize: NSSize) {
        guard newSize.width >= 1, newSize.height >= 1 else { return }
        super.setFrameSize(newSize)
    }
}
