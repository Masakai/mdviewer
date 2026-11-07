import XCTest
@testable import MDViewer

/// File > Duplicate / Rename… / Move To… のうち、URL の計算と実ファイルの移動。
@MainActor
final class DocumentViewModelRelocateTests: XCTestCase {
    private var tempDir: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var store: OpenDocumentStore!
    private var sut: DocumentViewModel!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DocumentViewModelRelocateTests-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        // 復元一覧をユーザーの設定に書き込まないよう、使い捨ての UserDefaults を使う
        suiteName = "DocumentViewModelRelocateTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        store = OpenDocumentStore(defaults: defaults)
        sut = DocumentViewModel(openDocumentStore: store, settings: defaults)
    }

    override func tearDown() async throws {
        sut = nil
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    private func makeFile(_ name: String, in folder: URL? = nil, content: String = "# A") throws -> URL {
        let url = (folder ?? tempDir).appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - renamedURL

    func test_renamedURL_keepsFolder() {
        let url = URL(fileURLWithPath: "/tmp/docs/a.md")
        XCTAssertEqual(DocumentViewModel.renamedURL(from: url, newName: "b.markdown")?.path, "/tmp/docs/b.markdown")
    }

    func test_renamedURL_addsOriginalExtensionWhenOmitted() {
        let url = URL(fileURLWithPath: "/tmp/docs/a.markdown")
        XCTAssertEqual(DocumentViewModel.renamedURL(from: url, newName: "  b  ")?.path, "/tmp/docs/b.markdown")
    }

    func test_renamedURL_rejectsEmptyAndPathLikeNames() {
        let url = URL(fileURLWithPath: "/tmp/docs/a.md")
        for name in ["", "   ", ".", "..", "../b.md", "sub/b.md", "b:c.md"] {
            XCTAssertNil(DocumentViewModel.renamedURL(from: url, newName: name), name)
        }
    }

    func test_movedURL_keepsName() {
        let url = URL(fileURLWithPath: "/tmp/docs/a.md")
        let folder = URL(fileURLWithPath: "/tmp/other", isDirectory: true)
        XCTAssertEqual(DocumentViewModel.movedURL(from: url, toFolder: folder).path, "/tmp/other/a.md")
    }

    // MARK: - duplicate

    func test_duplicateFileName_keepsExtension() {
        let name = DocumentViewModel.duplicateFileName(for: URL(fileURLWithPath: "/tmp/notes.markdown"))
        XCTAssertTrue(name.hasPrefix("notes"))
        XCTAssertTrue(name.hasSuffix(".markdown"))
        XCTAssertNotEqual(name, "notes.markdown")
    }

    func test_duplicateFileName_withoutFile_usesMarkdownExtension() {
        XCTAssertTrue(DocumentViewModel.duplicateFileName(for: nil).hasSuffix(".md"))
    }

    func test_newDocumentDuplicating_isUnsavedWithText() {
        sut.newDocument(duplicating: "# Copy", suggestedFileName: "a copy.md")
        XCTAssertNil(sut.fileURL)
        XCTAssertEqual(sut.text, "# Copy")
        XCTAssertTrue(sut.isDirty)
        XCTAssertTrue(sut.hasDocument)
        XCTAssertEqual(sut.suggestedFileName, "a copy.md")
    }

    // MARK: - relocate

    func test_relocate_rename_movesFileAndUpdatesState() throws {
        let url = try makeFile("a.md")
        sut.load(url: url)
        let newURL = try XCTUnwrap(DocumentViewModel.renamedURL(from: url, newName: "b"))

        try sut.relocate(to: newURL)

        XCTAssertEqual(sut.fileURL?.path, tempDir.appendingPathComponent("b.md").path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(try String(contentsOf: newURL, encoding: .utf8), "# A")
        // 復元一覧には新しい場所が1件だけ残る
        XCTAssertEqual(store.claimLaunchURLs().map(\.lastPathComponent), ["b.md"])
    }

    func test_relocate_toOtherFolder_movesFile() throws {
        let url = try makeFile("a.md")
        let folder = tempDir.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        sut.load(url: url)

        try sut.relocate(to: DocumentViewModel.movedURL(from: url, toFolder: folder))

        XCTAssertEqual(sut.fileURL?.path, folder.appendingPathComponent("a.md").path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("a.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func test_relocate_existingFile_throwsAndKeepsBoth() throws {
        let url = try makeFile("a.md", content: "A")
        let other = try makeFile("b.md", content: "B")
        sut.load(url: url)

        XCTAssertThrowsError(try sut.relocate(to: other)) { error in
            XCTAssertEqual(error as? DocumentRelocationError, .alreadyExists("b.md"))
        }
        XCTAssertEqual(sut.fileURL, url)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "A")
        XCTAssertEqual(try String(contentsOf: other, encoding: .utf8), "B")
    }

    func test_relocate_caseOnlyRename_isNotACollision() throws {
        let url = try makeFile("a.md")
        sut.load(url: url)
        let newURL = tempDir.appendingPathComponent("A.md")

        try sut.relocate(to: newURL)

        XCTAssertEqual(sut.fileURL?.lastPathComponent, "A.md")
        let names = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
        XCTAssertEqual(names, ["A.md"])
    }

    func test_relocate_sameURL_doesNothing() throws {
        let url = try makeFile("a.md")
        sut.load(url: url)

        try sut.relocate(to: url)

        XCTAssertEqual(sut.fileURL, url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func test_relocate_withoutFile_doesNothing() throws {
        sut.newDocument()
        try sut.relocate(to: tempDir.appendingPathComponent("x.md"))
        XCTAssertNil(sut.fileURL)
    }
}
