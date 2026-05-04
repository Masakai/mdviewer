import WebKit

// Handles `mdviewer-local://` scheme requests to serve local image files
// to WKWebView while enforcing path security.
final class LocalSchemeHandler: NSObject, WKURLSchemeHandler {
    // The directory that contains the currently opened Markdown file.
    var baseDirectory: URL?

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              let host = url.host
        else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }

        // Reconstruct file path from the scheme URL: mdviewer-local://path/to/image.png
        let relativePath = url.path.isEmpty ? host : host + url.path
        guard let base = baseDirectory else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }

        let fileURL = base.appendingPathComponent(relativePath).standardized

        // Security: ensure the resolved path stays within the base directory
        guard fileURL.path.hasPrefix(base.standardized.path) else {
            urlSchemeTask.didFailWithError(URLError(.noPermissionsToReadFile))
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let mimeType = mimeType(for: fileURL.pathExtension)
            let response = URLResponse(
                url: url,
                mimeType: mimeType,
                expectedContentLength: data.count,
                textEncodingName: nil
            )
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        // No-op: tasks complete synchronously
    }

    private func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "png":  return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif":  return "image/gif"
        case "svg":  return "image/svg+xml"
        case "webp": return "image/webp"
        default:     return "application/octet-stream"
        }
    }
}
