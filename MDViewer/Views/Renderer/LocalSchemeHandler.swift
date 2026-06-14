import WebKit

/// Handles `mdviewer-local://` scheme requests to serve local image files
/// to WKWebView while enforcing path security.
final class LocalSchemeHandler: NSObject, WKURLSchemeHandler {
    /// The directory that contains the currently opened Markdown file.
    var baseDirectory: URL?

    func webView(_: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }

        guard let base = baseDirectory else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }

        // URL form: mdviewer-local://localhost/<relative-path>
        // The relative path lives in url.path; strip the leading slash and
        // percent-decode it before resolving against the base directory.
        let rawPath = url.path.hasPrefix("/") ? String(url.path.dropFirst()) : url.path
        let relativePath = rawPath.removingPercentEncoding ?? rawPath
        guard !relativePath.isEmpty else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }

        let fileURL = base.appendingPathComponent(relativePath).standardized

        // Security: ensure the resolved path stays within the base directory.
        // Append a trailing slash to the base so a sibling directory whose name
        // shares a prefix (e.g. /a/b vs /a/bc) cannot pass the check.
        let basePath = base.standardized.path
        let baseBoundary = basePath.hasSuffix("/") ? basePath : basePath + "/"
        guard fileURL.path == basePath || fileURL.path.hasPrefix(baseBoundary) else {
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

    func webView(_: WKWebView, stop _: any WKURLSchemeTask) {
        // No-op: tasks complete synchronously
    }

    private func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "png": "image/png"
        case "jpg", "jpeg": "image/jpeg"
        case "gif": "image/gif"
        case "svg": "image/svg+xml"
        case "webp": "image/webp"
        default: "application/octet-stream"
        }
    }
}
