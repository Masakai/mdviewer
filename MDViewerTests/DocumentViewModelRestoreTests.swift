import XCTest
@testable import MDViewer

@MainActor
final class DocumentViewModelRestoreTests: XCTestCase {
    var defaults: UserDefaults!
    var suiteName: String!
    var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "DocumentViewModelRestoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DocumentViewModelRestoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    private func makeFile(_ name: String) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try "# \(name)".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// 前回の終了時に `urls` が開かれていた状態を作り、次回起動のViewModelを返す。
    private func makeRelaunchedViewModel(previouslyOpen urls: [URL]) -> DocumentViewModel {
        let previous = OpenDocumentStore(defaults: defaults)
        urls.forEach { previous.add(url: $0) }
        return DocumentViewModel(openDocumentStore: OpenDocumentStore(defaults: defaults))
    }

    private func collectOpenInWindowURLs(_ body: () -> Void) -> [URL] {
        var received: [URL] = []
        let token = NotificationCenter.default.addObserver(
            forName: .openDocumentInWindow, object: nil, queue: nil
        ) { if let url = $0.object as? URL { received.append(url) } }
        defer { NotificationCenter.default.removeObserver(token) }
        body()
        return received
    }

    // MARK: - 記録

    func test_load_recordsFileForNextLaunch() throws {
        let url = try makeFile("a.md")
        let sut = DocumentViewModel(openDocumentStore: OpenDocumentStore(defaults: defaults))

        sut.load(url: url)

        let next = OpenDocumentStore(defaults: defaults)
        XCTAssertEqual(next.claimLaunchURLs().map(\.lastPathComponent), ["a.md"])
    }

    // MARK: - 復元

    func test_restore_multipleFiles_firstLoadsHere_restOpenInNewWindows() throws {
        let a = try makeFile("a.md")
        let b = try makeFile("b.md")
        let c = try makeFile("c.md")
        let sut = makeRelaunchedViewModel(previouslyOpen: [a, b, c])

        let opened = collectOpenInWindowURLs { sut.restoreLastOpened() }

        XCTAssertEqual(sut.fileURL?.lastPathComponent, "a.md")
        XCTAssertEqual(sut.text, "# a.md")
        XCTAssertEqual(opened.map(\.lastPathComponent), ["b.md", "c.md"])
    }

    func test_restore_singleFile_doesNotOpenExtraWindows() throws {
        let sut = try makeRelaunchedViewModel(previouslyOpen: [makeFile("a.md")])

        let opened = collectOpenInWindowURLs { sut.restoreLastOpened() }

        XCTAssertEqual(sut.fileURL?.lastPathComponent, "a.md")
        XCTAssertTrue(opened.isEmpty)
    }

    func test_restore_noRecords_staysOnWelcomeScreen() {
        let sut = makeRelaunchedViewModel(previouslyOpen: [])

        let opened = collectOpenInWindowURLs { sut.restoreLastOpened() }

        XCTAssertFalse(sut.hasDocument)
        XCTAssertNil(sut.fileURL)
        XCTAssertTrue(opened.isEmpty)
    }

    func test_restore_firstFileDeleted_loadsNextExistingFile() throws {
        let a = try makeFile("a.md")
        let b = try makeFile("b.md")
        let sut = makeRelaunchedViewModel(previouslyOpen: [a, b])
        try FileManager.default.removeItem(at: a)

        sut.restoreLastOpened()

        XCTAssertEqual(sut.fileURL?.lastPathComponent, "b.md")
    }

    func test_restore_allFilesDeleted_staysOnWelcomeScreen() throws {
        let a = try makeFile("a.md")
        let sut = makeRelaunchedViewModel(previouslyOpen: [a])
        try FileManager.default.removeItem(at: a)

        sut.restoreLastOpened()

        XCTAssertFalse(sut.hasDocument)
    }

    func test_restore_secondWelcomeWindow_doesNotRestoreAgain() throws {
        let a = try makeFile("a.md")
        let store = OpenDocumentStore(defaults: defaults)
        store.add(url: a)
        let launchStore = OpenDocumentStore(defaults: defaults)
        let first = DocumentViewModel(openDocumentStore: launchStore)
        let second = DocumentViewModel(openDocumentStore: launchStore)

        first.restoreLastOpened()
        second.restoreLastOpened()

        XCTAssertEqual(first.fileURL?.lastPathComponent, "a.md")
        XCTAssertFalse(second.hasDocument)
    }
}
