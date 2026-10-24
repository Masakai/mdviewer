import Combine
import XCTest
@testable import MDViewer

/// 本物の NSDocumentController と同じく、新しいものを先頭に置き、重複は1件にまとめる偽物。
@MainActor
private final class FakeRecentDocumentController: RecentDocumentControlling {
    var recentDocumentURLs: [URL] = []
    var clearCount = 0

    func noteNewRecentDocumentURL(_ url: URL) {
        recentDocumentURLs.removeAll { $0 == url }
        recentDocumentURLs.insert(url, at: 0)
    }

    func clearRecentDocuments(_: Any?) {
        clearCount += 1
        recentDocumentURLs = []
    }
}

@MainActor
final class RecentDocumentsTests: XCTestCase {
    private var controller: FakeRecentDocumentController!
    private var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        controller = FakeRecentDocumentController()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecentDocumentsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        controller = nil
        try await super.tearDown()
    }

    private func makeFile(_ name: String) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try "# \(name)".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - 一覧

    func test_init_readsExistingEntries() {
        let a = URL(fileURLWithPath: "/tmp/a.md")
        controller.recentDocumentURLs = [a]

        let sut = RecentDocuments(controller: controller)

        XCTAssertEqual(sut.urls, [a])
    }

    func test_note_updatesListWithMostRecentFirst() {
        let sut = RecentDocuments(controller: controller)
        let a = URL(fileURLWithPath: "/tmp/a.md")
        let b = URL(fileURLWithPath: "/tmp/b.md")

        sut.note(url: a)
        sut.note(url: b)

        XCTAssertEqual(sut.urls, [b, a])
    }

    func test_note_publishesChange() {
        let sut = RecentDocuments(controller: controller)
        var changeCount = 0
        let cancellable = sut.objectWillChange.sink { changeCount += 1 }
        defer { cancellable.cancel() }

        sut.note(url: URL(fileURLWithPath: "/tmp/a.md"))

        XCTAssertEqual(changeCount, 1)
    }

    // MARK: - 消去

    func test_clear_emptiesList() {
        let sut = RecentDocuments(controller: controller)
        sut.note(url: URL(fileURLWithPath: "/tmp/a.md"))

        sut.clear()

        XCTAssertEqual(controller.clearCount, 1)
        XCTAssertTrue(sut.urls.isEmpty)
    }

    // MARK: - DocumentViewModel からの記録

    func test_documentLoad_notesURL() throws {
        let recent = RecentDocuments(controller: controller)
        let suiteName = "RecentDocumentsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let documentVM = DocumentViewModel(
            openDocumentStore: OpenDocumentStore(defaults: defaults),
            settings: defaults,
            recentDocuments: recent
        )
        let url = try makeFile("a.md")

        documentVM.load(url: url)

        XCTAssertEqual(recent.urls, [url])
    }

    func test_documentLoad_failure_doesNotNoteURL() throws {
        let recent = RecentDocuments(controller: controller)
        let suiteName = "RecentDocumentsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let documentVM = DocumentViewModel(
            openDocumentStore: OpenDocumentStore(defaults: defaults),
            settings: defaults,
            recentDocuments: recent
        )

        documentVM.load(url: tempDir.appendingPathComponent("missing.md"))

        XCTAssertTrue(recent.urls.isEmpty)
    }
}
