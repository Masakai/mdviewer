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
        contentController.add(context.coordinator, name: "scrollPositionChanged")
        contentController.add(context.coordinator, name: "linkHovered")
        contentController.add(context.coordinator, name: "linkClicked")
        config.userContentController = contentController

        // Register custom scheme for local images
        config.setURLSchemeHandler(context.coordinator.schemeHandler, forURLScheme: "mdviewer-local")

        // Allow local file access
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsLinkPreview = false
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator

        context.coordinator.webView = webView
        renderVM.webView = webView
        renderVM.schemeHandler = context.coordinator.schemeHandler

        loadRenderer(webView: webView)

        return webView
    }

    func updateNSView(_: WKWebView, context _: Context) {
        // Content updates are driven by RenderViewModel, not SwiftUI updates
    }

    private func loadRenderer(webView: WKWebView) {
        guard let rendererURL = HTMLBuilder.rendererURL(),
              let resourcesDir = HTMLBuilder.webResourcesDirectory()
        else { return }

        webView.loadFileURL(rendererURL, allowingReadAccessTo: resourcesDir)
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
                handleRenderComplete()
            case "scrollPositionChanged":
                break
            case "linkHovered":
                let url = message.body as? String ?? ""
                Task { @MainActor in self.renderVM.hoveredURL = url }
            case "linkClicked":
                guard let urlString = message.body as? String,
                      let url = URL(string: urlString) else { break }
                Task { @MainActor in
                    if url.scheme == "file",
                       ["md", "markdown"].contains(url.pathExtension.lowercased())
                    {
                        NotificationCenter.default.post(name: .openLocalDocument, object: url)
                    } else {
                        NSWorkspace.shared.open(url)
                    }
                }
            default:
                break
            }
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

        private func handleRenderComplete() {}

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

            decisionHandler(.allow)
        }
    }
}
