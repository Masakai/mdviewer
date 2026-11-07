import AppKit
import XCTest
@testable import MDViewer

/// 書き込めないファイル（Finder のロック・書き込み権限なし）は保存せず、エディタで編集させない（#37）
@MainActor
final class DocumentViewModelReadOnlyTests: XCTestCase {
    private static let suiteName = "com.mdviewer.app.tests.DocumentViewModelReadOnly"
    private var defaults: UserDefaults!
    private var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        UserDefaults().removePersistentDomain(forName: Self.suiteName)
        defaults = UserDefaults(suiteName: Self.suiteName)
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DocumentViewModelReadOnlyTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: Self.suiteName)
        // ロックしたファイルは外さないと消せない。テストが途中で失敗しても後始末できるようここで外す
        if let names = try? FileManager.default.contentsOfDirectory(atPath: tempDir.path) {
            for name in names {
                try? FileManager.default.setAttributes(
                    [.immutable: false, .posixPermissions: 0o644],
                    ofItemAtPath: tempDir.appendingPathComponent(name).path
                )
            }
        }
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    private func makeFile(_ name: String, content: String) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// chmod 444 相当。フォルダには書き込めるので、atomic な書き込みは通ってしまう
    private func makeWriteProtectedFile(_ name: String, content: String) throws -> URL {
        let url = try makeFile(name, content: content)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: url.path)
        return url
    }

    /// Finder の「ロック」（chflags uchg）
    private func makeLockedFile(_ name: String, content: String) throws -> URL {
        let url = try makeFile(name, content: content)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: url.path)
        return url
    }

    private func makeViewModel() -> DocumentViewModel {
        DocumentViewModel(openDocumentStore: OpenDocumentStore(defaults: defaults), settings: defaults)
    }

    private func contents(of url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - 判定

    func test_load_writableFile_isNotReadOnly() throws {
        let sut = makeViewModel()

        try sut.load(url: makeFile("a.md", content: "# a"))

        XCTAssertFalse(sut.isReadOnly)
    }

    func test_load_writeProtectedFile_isReadOnly() throws {
        let sut = makeViewModel()

        try sut.load(url: makeWriteProtectedFile("a.md", content: "# a"))

        XCTAssertTrue(sut.isReadOnly)
        XCTAssertEqual(sut.text, "# a")
    }

    func test_load_lockedFile_isReadOnly() throws {
        let sut = makeViewModel()

        try sut.load(url: makeLockedFile("a.md", content: "# a"))

        XCTAssertTrue(sut.isReadOnly)
        XCTAssertEqual(sut.text, "# a")
    }

    func test_newDocument_afterReadOnlyFile_isNotReadOnly() throws {
        let sut = makeViewModel()
        try sut.load(url: makeLockedFile("a.md", content: "# a"))

        sut.newDocument()

        XCTAssertFalse(sut.isReadOnly)
    }

    func test_refreshReadOnly_afterUnlocking_becomesWritable() throws {
        let sut = makeViewModel()
        let url = try makeLockedFile("a.md", content: "# a")
        sut.load(url: url)
        XCTAssertTrue(sut.isReadOnly)

        try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: url.path)
        sut.refreshReadOnly()

        XCTAssertFalse(sut.isReadOnly)
    }

    func test_refreshReadOnly_afterRemovingWritePermission_becomesReadOnly() throws {
        let sut = makeViewModel()
        let url = try makeFile("a.md", content: "# a")
        sut.load(url: url)
        XCTAssertFalse(sut.isReadOnly)

        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: url.path)
        sut.refreshReadOnly()

        XCTAssertTrue(sut.isReadOnly)
    }

    /// 自動再読み込みがオフでも、ファイル監視の通知で保存できるかどうかは調べ直す（本文は読み直さない）
    func test_fileDidChange_autoReloadOff_updatesReadOnlyWithoutReloading() throws {
        defaults.set(false, forKey: DocumentViewModel.autoReloadKey)
        let sut = makeViewModel()
        let url = try makeFile("a.md", content: "# a")
        sut.load(url: url)
        try "# changed".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: url.path)

        sut.fileDidChange()

        XCTAssertTrue(sut.isReadOnly)
        XCTAssertEqual(sut.text, "# a")
    }

    func test_reload_updatesReadOnly() throws {
        let sut = makeViewModel()
        let url = try makeFile("a.md", content: "# a")
        sut.load(url: url)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: url.path)

        sut.reload()

        XCTAssertTrue(sut.isReadOnly)
    }

    // MARK: - 保存

    func test_save_writableFile_writesContents() throws {
        let sut = makeViewModel()
        let url = try makeFile("a.md", content: "# a")
        sut.load(url: url)
        sut.updateText("# edited")

        sut.save()

        XCTAssertEqual(try contents(of: url), "# edited")
        XCTAssertFalse(sut.isDirty)
        XCTAssertNil(sut.errorMessage)
    }

    /// 書き込み権限がなくてもフォルダに書き込めると、atomic な書き込みが通って中身が置き換わっていた
    func test_save_writeProtectedFile_doesNotOverwriteAndReportsError() throws {
        let sut = makeViewModel()
        let url = try makeWriteProtectedFile("a.md", content: "# a")
        sut.load(url: url)
        sut.updateText("# edited")

        sut.save()

        XCTAssertEqual(try contents(of: url), "# a")
        XCTAssertNotNil(sut.errorMessage)
        // 閉じるときの「保存」で errorMessage を見てウィンドウを閉じずに残すので、変更も残っていること
        XCTAssertTrue(sut.isDirty)
        XCTAssertEqual(sut.text, "# edited")
    }

    func test_save_lockedFile_doesNotOverwriteAndReportsError() throws {
        let sut = makeViewModel()
        let url = try makeLockedFile("a.md", content: "# a")
        sut.load(url: url)
        sut.updateText("# edited")

        sut.save()

        XCTAssertEqual(try contents(of: url), "# a")
        XCTAssertNotNil(sut.errorMessage)
        XCTAssertTrue(sut.isDirty)
    }

    /// 編集した後にロックされた場合も、保存の直前に調べ直して書き込まない
    func test_save_lockedAfterLoading_doesNotOverwrite() throws {
        let sut = makeViewModel()
        let url = try makeFile("a.md", content: "# a")
        sut.load(url: url)
        sut.updateText("# edited")
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: url.path)

        sut.save()

        XCTAssertEqual(try contents(of: url), "# a")
        XCTAssertNotNil(sut.errorMessage)
        XCTAssertTrue(sut.isReadOnly)
        XCTAssertTrue(sut.isDirty)
    }

    func test_save_afterUnlocking_writesContents() throws {
        let sut = makeViewModel()
        let url = try makeLockedFile("a.md", content: "# a")
        sut.load(url: url)
        sut.updateText("# edited")
        try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: url.path)

        sut.save()

        XCTAssertEqual(try contents(of: url), "# edited")
        XCTAssertFalse(sut.isReadOnly)
        XCTAssertNil(sut.errorMessage)
    }

    /// メッセージには保存できなかったファイルの名前を入れる
    func test_save_readOnly_messageNamesTheFile() throws {
        let sut = makeViewModel()
        try sut.load(url: makeLockedFile("notes.md", content: "# a"))
        sut.updateText("# edited")

        sut.save()

        XCTAssertTrue(try XCTUnwrap(sut.errorMessage).contains("notes.md"))
    }
}

// MARK: - 編集できないエディタ

/// エディタは isReadOnly のとき isEditable = false にする。そのとき検索の置換が本文を変えないこと
@MainActor
final class ReadOnlyEditorTests: XCTestCase {
    private var window: NSWindow!
    private var textView: NSTextView!
    private var sut: EditorSearchController!

    override func setUp() async throws {
        let (scrollView, editorTextView) = MarkdownEditorView.makeTextView()
        textView = editorTextView
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = scrollView
        sut = EditorSearchController()
        sut.textView = textView
    }

    override func tearDown() async throws {
        window.close()
        window = nil
        textView = nil
        sut = nil
    }

    func test_replaceCurrent_notEditable_leavesTextUnchanged() {
        textView.string = "cat cat"
        textView.isEditable = false
        sut.search("cat", selecting: true)

        sut.replaceCurrent(with: "dog")

        XCTAssertEqual(textView.string, "cat cat")
    }

    func test_replaceAll_notEditable_leavesTextUnchanged() {
        textView.string = "cat cat"
        textView.isEditable = false
        sut.search("cat", selecting: true)

        let count = sut.replaceAll(with: "dog")

        XCTAssertEqual(count, 0)
        XCTAssertEqual(textView.string, "cat cat")
    }

    /// 編集できなくしても、選択とコピーはできる
    func test_notEditable_staysSelectable() {
        textView.string = "cat cat"
        textView.isEditable = false

        XCTAssertTrue(textView.isSelectable)
    }

    /// 編集してから読み取り専用になったファイルでは、取り消しでも本文を変えない
    func test_undo_afterBecomingNotEditable_leavesTextUnchanged() throws {
        textView.string = "cat"
        textView.setSelectedRange(NSRange(location: 3, length: 0))
        textView.insertText("s", replacementRange: textView.selectedRange())
        let undoManager = try XCTUnwrap(textView.undoManager)
        XCTAssertEqual(textView.string, "cats")
        XCTAssertTrue(undoManager.canUndo)
        textView.isEditable = false

        undoManager.undo()

        XCTAssertEqual(textView.string, "cats")
    }

    /// 上のテストの対照。編集できるときは同じ手順で取り消せる
    func test_undo_editable_revertsText() throws {
        textView.string = "cat"
        textView.setSelectedRange(NSRange(location: 3, length: 0))
        textView.insertText("s", replacementRange: textView.selectedRange())
        let undoManager = try XCTUnwrap(textView.undoManager)

        undoManager.undo()

        XCTAssertEqual(textView.string, "cat")
    }
}
