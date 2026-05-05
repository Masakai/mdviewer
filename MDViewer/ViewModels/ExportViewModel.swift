import SwiftUI
import WebKit

@MainActor
final class ExportViewModel: ObservableObject {
    @Published var isExporting: Bool = false
    @Published var errorMessage: String?

    func exportToPDF(webView: WKWebView, pageSize: PDFPageSize = .a4) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "document.pdf"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        isExporting = true

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
            isExporting = false
            return
        }
        op.runModal(for: window, delegate: self, didRun: #selector(printOperationDidRun(_:success:contextInfo:)), contextInfo: UnsafeMutableRawPointer(bitPattern: 0))
    }

    @objc private func printOperationDidRun(_ op: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        isExporting = false
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
