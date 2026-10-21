import WebKit
import XCTest
@testable import MDViewer

final class WebRendererViewTests: XCTestCase {
    // MARK: - isSupersededNavigation

    /// WebKit reports a navigation replaced by a newer one as an NSError in
    /// NSURLErrorDomain, not as a Swift URLError. It must still be recognised.
    func test_isSupersededNavigation_cancelledNSError_returnsTrue() {
        // Arrange
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)

        // Act
        let result = WebRendererView.Coordinator.isSupersededNavigation(error)

        // Assert
        XCTAssertTrue(result)
    }

    /// A renderer page that genuinely fails to load has to be recovered.
    func test_isSupersededNavigation_fileDoesNotExist_returnsFalse() {
        // Arrange
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorFileDoesNotExist)

        // Act
        let result = WebRendererView.Coordinator.isSupersededNavigation(error)

        // Assert
        XCTAssertFalse(result)
    }

    func test_isSupersededNavigation_webKitError_returnsFalse() {
        // Arrange
        let error = NSError(
            domain: WKError.errorDomain,
            code: WKError.Code.webContentProcessTerminated.rawValue
        )

        // Act
        let result = WebRendererView.Coordinator.isSupersededNavigation(error)

        // Assert
        XCTAssertFalse(result)
    }

    // MARK: - resolveLinkURL

    private let docsDir = URL(fileURLWithPath: "/Users/me/docs/", isDirectory: true)

    private func resolve(_ href: String, _ dir: URL? = nil) -> URL? {
        WebRendererView.Coordinator.resolveLinkURL(href, relativeTo: dir ?? docsDir)
    }

    /// Relative links point at the open file's directory, not the app bundle (#22).
    func test_resolveLinkURL_subdirectory_resolvesAgainstDocumentDirectory() {
        XCTAssertEqual(resolve("dir_name/file_name.md")?.path, "/Users/me/docs/dir_name/file_name.md")
    }

    func test_resolveLinkURL_dotSlash_resolvesToSameDirectory() {
        XCTAssertEqual(resolve("./same.md")?.path, "/Users/me/docs/same.md")
    }

    func test_resolveLinkURL_parentDirectory_collapsesDotDot() {
        let url = resolve("../dir_name/file_name.md")

        XCTAssertEqual(url?.absoluteString, "file:///Users/me/dir_name/file_name.md")
    }

    func test_resolveLinkURL_absolutePath_staysAbsolute() {
        XCTAssertEqual(resolve("/path/to/file.md")?.absoluteString, "file:///path/to/file.md")
    }

    /// A base without a trailing slash would otherwise drop its last component.
    func test_resolveLinkURL_baseWithoutTrailingSlash_keepsLastComponent() throws {
        let dir = try XCTUnwrap(URL(string: "file:///Users/me/docs"))

        XCTAssertEqual(resolve("file.md", dir)?.path, "/Users/me/docs/file.md")
    }

    func test_resolveLinkURL_percentEncodedName_decodesToPath() {
        XCTAssertEqual(resolve("my%20notes/%E8%B3%87%E6%96%99.md")?.path, "/Users/me/docs/my notes/資料.md")
    }

    func test_resolveLinkURL_unencodedName_resolves() {
        XCTAssertEqual(resolve("my notes/資料.md")?.path, "/Users/me/docs/my notes/資料.md")
    }

    func test_resolveLinkURL_fragment_keepsMarkdownExtension() {
        let url = resolve("other.md#section")

        XCTAssertEqual(url?.path, "/Users/me/docs/other.md")
        XCTAssertEqual(url?.pathExtension, "md")
    }

    func test_resolveLinkURL_https_unchanged() {
        XCTAssertEqual(resolve("https://example.com/a?b=1")?.absoluteString, "https://example.com/a?b=1")
    }

    func test_resolveLinkURL_mailto_unchanged() {
        XCTAssertEqual(resolve("mailto:someone@example.com")?.absoluteString, "mailto:someone@example.com")
    }

    func test_resolveLinkURL_relativeWithoutOpenFile_returnsNil() {
        XCTAssertNil(WebRendererView.Coordinator.resolveLinkURL("file.md", relativeTo: nil))
    }

    func test_resolveLinkURL_absoluteURLWithoutOpenFile_resolves() {
        let url = WebRendererView.Coordinator.resolveLinkURL("https://example.com", relativeTo: nil)

        XCTAssertEqual(url?.absoluteString, "https://example.com")
    }

    // MARK: - RendererWebView

    /// HSplitView sends a zero-height frame on every live-resize step; applying
    /// it would make the page lay out in an empty viewport (white flash).
    func test_setFrameSize_zeroHeight_keepsPreviousSize() {
        // Arrange
        let webView = RendererWebView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))

        // Act
        webView.setFrameSize(NSSize(width: 780, height: 0))

        // Assert
        XCTAssertEqual(webView.frame.size, NSSize(width: 300, height: 200))
    }

    func test_setFrameSize_zeroWidth_keepsPreviousSize() {
        // Arrange
        let webView = RendererWebView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))

        // Act
        webView.setFrameSize(NSSize(width: 0, height: 700))

        // Assert
        XCTAssertEqual(webView.frame.size, NSSize(width: 300, height: 200))
    }

    func test_setFrameSize_realSize_isApplied() {
        // Arrange
        let webView = RendererWebView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))

        // Act
        webView.setFrameSize(NSSize(width: 400, height: 300))

        // Assert
        XCTAssertEqual(webView.frame.size, NSSize(width: 400, height: 300))
    }
}
