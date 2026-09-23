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
}
