import XCTest
@testable import MDViewer

@MainActor
final class DocumentViewModelTests: XCTestCase {

    var sut: DocumentViewModel!
    var tempDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()
        sut = DocumentViewModel()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        sut = nil
        try? FileManager.default.removeItem(at: tempDirectory)
        tempDirectory = nil
        try await super.tearDown()
    }

    // MARK: - load(url:) happy path

    func test_load_validMarkdownFile_setsTextContent() throws {
        // Arrange
        let content = "# Hello\n\nThis is a test."
        let fileURL = tempDirectory.appendingPathComponent("test.md")
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        // Act
        sut.load(url: fileURL)

        // Assert
        XCTAssertEqual(sut.text, content)
        XCTAssertNil(sut.errorMessage)
        XCTAssertFalse(sut.isLoading)
    }

    func test_load_validMarkdownFile_setsFileURL() throws {
        // Arrange
        let fileURL = tempDirectory.appendingPathComponent("test.md")
        try "# Hello".write(to: fileURL, atomically: true, encoding: .utf8)

        // Act
        sut.load(url: fileURL)

        // Assert
        XCTAssertEqual(sut.fileURL, fileURL)
    }

    func test_load_validFile_isLoadingIsFalseAfterLoad() throws {
        // Arrange
        let fileURL = tempDirectory.appendingPathComponent("test.md")
        try "content".write(to: fileURL, atomically: true, encoding: .utf8)

        // Act
        sut.load(url: fileURL)

        // Assert
        XCTAssertFalse(sut.isLoading)
    }

    func test_load_emptyFile_setsEmptyText() throws {
        // Arrange
        let fileURL = tempDirectory.appendingPathComponent("empty.md")
        try "".write(to: fileURL, atomically: true, encoding: .utf8)

        // Act
        sut.load(url: fileURL)

        // Assert
        XCTAssertEqual(sut.text, "")
        XCTAssertNil(sut.errorMessage)
    }

    // MARK: - load(url:) error handling

    func test_load_nonExistentFile_setsErrorMessage() {
        // Arrange
        let missingURL = tempDirectory.appendingPathComponent("does_not_exist.md")

        // Act
        sut.load(url: missingURL)

        // Assert
        XCTAssertNotNil(sut.errorMessage)
        XCTAssertFalse(sut.isLoading)
    }

    func test_load_nonExistentFile_doesNotChangeFileURL() {
        // Arrange
        let missingURL = tempDirectory.appendingPathComponent("does_not_exist.md")
        let previousURL = sut.fileURL

        // Act
        sut.load(url: missingURL)

        // Assert
        XCTAssertEqual(sut.fileURL, previousURL)
    }

    func test_load_afterPreviousError_clearsPreviousErrorMessage() throws {
        // Arrange — first load fails
        let missingURL = tempDirectory.appendingPathComponent("missing.md")
        sut.load(url: missingURL)
        XCTAssertNotNil(sut.errorMessage)

        // Now load a valid file
        let validURL = tempDirectory.appendingPathComponent("valid.md")
        try "# Hello".write(to: validURL, atomically: true, encoding: .utf8)

        // Act
        sut.load(url: validURL)

        // Assert
        XCTAssertNil(sut.errorMessage)
    }

    // MARK: - reload

    func test_reload_withNoFileURL_doesNothing() {
        // Arrange
        XCTAssertNil(sut.fileURL)

        // Act — should not crash
        sut.reload()

        // Assert
        XCTAssertEqual(sut.text, "")
        XCTAssertNil(sut.errorMessage)
    }

    func test_reload_withValidFileURL_refreshesText() throws {
        // Arrange
        let fileURL = tempDirectory.appendingPathComponent("test.md")
        try "original content".write(to: fileURL, atomically: true, encoding: .utf8)
        sut.load(url: fileURL)
        XCTAssertEqual(sut.text, "original content")

        // Modify the file
        try "updated content".write(to: fileURL, atomically: true, encoding: .utf8)

        // Act
        sut.reload()

        // Assert
        XCTAssertEqual(sut.text, "updated content")
    }

    func test_reload_fileDeletedAfterLoad_setsErrorMessage() throws {
        // Arrange
        let fileURL = tempDirectory.appendingPathComponent("test.md")
        try "content".write(to: fileURL, atomically: true, encoding: .utf8)
        sut.load(url: fileURL)
        try FileManager.default.removeItem(at: fileURL)

        // Act
        sut.reload()

        // Assert
        XCTAssertNotNil(sut.errorMessage)
    }
}
