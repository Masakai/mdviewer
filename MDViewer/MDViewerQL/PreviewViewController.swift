import Cocoa
import Quartz

/// Phase 1 スパイク: .mdファイルの認識確認と親ディレクトリ画像アクセスの可否確認
final class PreviewViewController: NSViewController, QLPreviewingController {
    private let label = NSTextField(labelWithString: "")

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: 24)
        label.alignment = .center
        label.stringValue = "MDViewerQL: Loading…"
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            label.widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor, constant: -40),
        ])
        view = container
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let preview = String(text.prefix(200)).replacingOccurrences(of: "\n", with: " ")

            // 親ディレクトリ内の画像ファイルを列挙してアクセス可否を確認
            let dir = url.deletingLastPathComponent()
            let imageExts = Set(["png", "jpg", "jpeg", "gif", "svg", "webp"])
            var imageAccessLog = ""
            if let contents = try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil
            ) {
                let images = contents.filter { imageExts.contains($0.pathExtension.lowercased()) }
                for img in images.prefix(3) {
                    let accessible = (try? Data(contentsOf: img)) != nil
                    imageAccessLog += "\n\(img.lastPathComponent): \(accessible ? "OK" : "NG")"
                }
                if images.isEmpty { imageAccessLog = "\n(no images in directory)" }
            }

            DispatchQueue.main.async {
                self.label.stringValue = "✅ MDViewerQL\n\(preview)\(imageAccessLog)"
                handler(nil)
            }
        } catch {
            DispatchQueue.main.async {
                self.label.stringValue = "❌ Error: \(error.localizedDescription)"
                handler(error)
            }
        }
    }
}
