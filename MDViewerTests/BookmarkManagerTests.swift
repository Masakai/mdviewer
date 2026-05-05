import XCTest
@testable import MDViewer

final class BookmarkManagerTests: XCTestCase {

    var sut: BookmarkManager!
    private var writtenKeys: [String] = []

    override func setUp() {
        super.setUp()
        sut = BookmarkManager.shared
        writtenKeys = []
    }

    override func tearDown() {
        writtenKeys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        sut = nil
        super.tearDown()
    }

    // MARK: - resolve (missing data)

    func test_resolve_noBookmarkData_returnsNil() {
        // Arrange
        let unknownPath = "/tmp/nonexistent_test_path_\(UUID().uuidString)"

        // Act
        let result = sut.resolve(for: unknownPath)

        // Assert
        XCTAssertNil(result)
    }

    func test_resolve_afterUserDefaultsCleared_returnsNil() {
        // Arrange
        let path = "/tmp/some_path"
        // Ensure no data is stored for this key
        UserDefaults.standard.removeObject(forKey: "bookmark_" + path)

        // Act
        let result = sut.resolve(for: path)

        // Assert
        XCTAssertNil(result)
    }

    // MARK: - save (security-scoped resource)

    func test_save_fileOutsideSandbox_doesNotCrash() {
        // Arrange — normal temp file (not security-scoped, startAccessingSecurityScopedResource returns false)
        let url = URL(fileURLWithPath: "/tmp/test_bookmark_\(UUID().uuidString).md")
        writtenKeys.append("bookmark_" + url.path)

        // Act — should silently fail without crashing
        sut.save(url: url)

        // Assert — no crash is the expectation
    }

    // MARK: - startAccess / stopAccess

    func test_startAccess_returnsABoolWithoutCrashing() {
        // Arrange
        let url = URL(fileURLWithPath: "/tmp/test_\(UUID().uuidString).md")

        // Act — result depends on sandbox environment; just verify no crash
        let result = sut.startAccess(url: url)

        // Cleanup
        if result {
            sut.stopAccess(url: url)
        }
    }

    func test_stopAccess_doesNotCrash() {
        // Arrange
        let url = URL(fileURLWithPath: "/tmp/test_\(UUID().uuidString).md")

        // Act — should not crash
        sut.stopAccess(url: url)
    }

    // MARK: - singleton

    func test_shared_isSingleton() {
        // Assert
        XCTAssertTrue(BookmarkManager.shared === BookmarkManager.shared)
    }
}
