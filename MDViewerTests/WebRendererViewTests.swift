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
