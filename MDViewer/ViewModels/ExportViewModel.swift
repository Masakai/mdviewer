import SwiftUI
import WebKit

@MainActor
final class ExportViewModel: ObservableObject {
    @Published var isExporting: Bool = false
    @Published var errorMessage: String?

    func exportToPDF(webView: WKWebView) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "document.pdf"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        isExporting = true
        let config = WKPDFConfiguration()
        webView.createPDF(configuration: config) { [weak self] result in
            DispatchQueue.main.async {
                self?.isExporting = false
                switch result {
                case .success(let data):
                    do {
                        try data.write(to: url)
                    } catch {
                        self?.errorMessage = error.localizedDescription
                    }
                case .failure(let error):
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func exportToHTML(webView: WKWebView) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = "document.html"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        isExporting = true
        webView.evaluateJavaScript("document.documentElement.outerHTML") { [weak self] result, error in
            DispatchQueue.main.async {
                self?.isExporting = false
                if let html = result as? String {
                    do {
                        try html.write(to: url, atomically: true, encoding: .utf8)
                    } catch {
                        self?.errorMessage = error.localizedDescription
                    }
                } else if let error {
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func print(webView: WKWebView) {
        let op = webView.printOperation(with: NSPrintInfo.shared)
        op.run()
    }
}
