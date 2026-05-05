import SwiftUI
import WebKit

@MainActor
final class ExportViewModel: ObservableObject {
    @Published var isExporting: Bool = false
    @Published var errorMessage: String?

    func baseName(for url: URL?) -> String {
        guard let url else { return "document" }
        let raw = url.deletingPathExtension().lastPathComponent
        return raw.removingPercentEncoding ?? raw
    }

    func exportToPDF(webView: WKWebView, renderVM: RenderViewModel, sourceURL: URL? = nil, pageSize: PDFPageSize = .a4) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(baseName(for: sourceURL)).pdf"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        isExporting = true

        let doExport = { [weak self, weak webView] in
            guard let self, let webView else { return }
            webView.evaluateJavaScript("MDViewer.preparePrint()", completionHandler: nil)
            let info = NSPrintInfo.shared.copy() as! NSPrintInfo
            let pt = pageSize.pointSize
            info.paperSize = pt
            info.topMargin = 0
            info.bottomMargin = 0
            info.leftMargin = 0
            info.rightMargin = 0
            info.isHorizontallyCentered = false
            info.isVerticallyCentered = false
            info.jobDisposition = .save
            info.dictionary().setValue(url, forKey: NSPrintInfo.AttributeKey.jobSavingURL.rawValue)

            let op = webView.printOperation(with: info)
            op.showsPrintPanel = false
            op.showsProgressPanel = false

            guard let window = webView.window else {
                _ = op.run()
                self.isExporting = false
                return
            }
            op.runModal(for: window, delegate: self, didRun: #selector(self.printOperationDidRun(_:success:contextInfo:)), contextInfo: UnsafeMutableRawPointer(bitPattern: 0))
        }

        if renderVM.isContentReady {
            doExport()
        } else {
            renderVM.pendingExport = doExport
        }
    }

    @objc private func printOperationDidRun(_ op: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        isExporting = false
    }

    func exportToHTML(webView: WKWebView, sourceURL: URL? = nil) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = "\(baseName(for: sourceURL)).html"

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
