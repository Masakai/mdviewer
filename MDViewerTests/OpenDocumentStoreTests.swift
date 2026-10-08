import XCTest
@testable import MDViewer

final class OpenDocumentStoreTests: XCTestCase {
    var defaults: UserDefaults!
    var suiteName: String!
    var tempDir: URL!
    var sut: OpenDocumentStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "OpenDocumentStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenDocumentStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        sut = OpenDocumentStore(defaults: defaults)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: tempDir)
        sut = nil
        try super.tearDownWithError()
    }

    private func makeFile(_ name: String) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try "# \(name)".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func claimed(_ store: OpenDocumentStore? = nil) -> [String] {
        (store ?? sut).claimLaunchURLs().map(\.lastPathComponent)
    }

    // MARK: - 複数ファイルの記録と復元

    func test_add_multipleFiles_allRestoredInOrder() throws {
        try sut.add(url: makeFile("a.md"))
        try sut.add(url: makeFile("b.md"))
        try sut.add(url: makeFile("c.md"))

        // 新しいインスタンス = 次回起動
        XCTAssertEqual(claimed(OpenDocumentStore(defaults: defaults)), ["a.md", "b.md", "c.md"])
    }

    func test_add_sameFileTwice_recordedOnce() throws {
        let url = try makeFile("a.md")
        sut.add(url: url)
        sut.add(url: url)

        XCTAssertEqual(claimed(OpenDocumentStore(defaults: defaults)), ["a.md"])
    }

    // MARK: - ウィンドウを閉じたとき

    func test_remove_closedFileNotRestored() throws {
        let a = try makeFile("a.md")
        sut.add(url: a)
        try sut.add(url: makeFile("b.md"))

        sut.remove(url: a)

        XCTAssertEqual(claimed(OpenDocumentStore(defaults: defaults)), ["b.md"])
    }

    func test_remove_lastRemainingFile_isKept() throws {
        let a = try makeFile("a.md")
        sut.add(url: a)

        sut.remove(url: a)

        XCTAssertEqual(claimed(OpenDocumentStore(defaults: defaults)), ["a.md"])
    }

    func test_remove_whenTerminating_keepsAll() throws {
        let a = try makeFile("a.md")
        sut.add(url: a)
        try sut.add(url: makeFile("b.md"))
        sut.isTerminating = true

        sut.remove(url: a)

        XCTAssertEqual(claimed(OpenDocumentStore(defaults: defaults)), ["a.md", "b.md"])
    }

    // MARK: - 復元時の取り扱い

    func test_claim_skipsDeletedFiles() throws {
        let a = try makeFile("a.md")
        sut.add(url: a)
        try sut.add(url: makeFile("b.md"))
        try FileManager.default.removeItem(at: a)

        XCTAssertEqual(claimed(OpenDocumentStore(defaults: defaults)), ["b.md"])
    }

    func test_claim_allFilesDeleted_returnsEmpty() throws {
        let a = try makeFile("a.md")
        sut.add(url: a)
        try FileManager.default.removeItem(at: a)

        XCTAssertTrue(claimed(OpenDocumentStore(defaults: defaults)).isEmpty)
    }

    func test_claim_returnsValuesOnlyOncePerLaunch() throws {
        try sut.add(url: makeFile("a.md"))
        let next = OpenDocumentStore(defaults: defaults)

        XCTAssertEqual(claimed(next), ["a.md"])
        XCTAssertTrue(claimed(next).isEmpty)
    }

    func test_claim_noRecords_returnsEmpty() {
        XCTAssertTrue(claimed().isEmpty)
    }

    // MARK: - 旧バージョンからの引き継ぎ

    func test_claim_legacySingleBookmark_isRestored() throws {
        let url = try makeFile("legacy.md")
        let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(data, forKey: "lastOpenedBookmark")

        XCTAssertEqual(claimed(), ["legacy.md"])
    }
}
