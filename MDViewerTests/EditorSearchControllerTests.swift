import AppKit
import XCTest
@testable import MDViewer

// MARK: - 一致の判定

final class EditorSearchRangesTests: XCTestCase {
    private func found(_ query: String, in text: String) -> [String] {
        EditorSearchController.ranges(of: query, in: text).map { (text as NSString).substring(with: $0) }
    }

    func test_ranges_ignoresCase() {
        XCTAssertEqual(found("swift", in: "Swift and SWIFT and swift"), ["Swift", "SWIFT", "swift"])
    }

    /// プレビューと同じく、検索語の空白は空白の並びや1つの改行に一致する
    func test_ranges_spaceMatchesRunOfSpacesAndSingleLineBreak() {
        XCTAssertEqual(
            found("foo bar", in: "foo   bar / foo\nbar / foo \n  bar"),
            ["foo   bar", "foo\nbar", "foo \n  bar"]
        )
    }

    /// 空行（段落の区切り）はまたがない。プレビューが段落をまたがないのと揃える
    func test_ranges_doesNotCrossBlankLine() {
        XCTAssertEqual(found("foo bar", in: "foo\n\nbar"), [])
    }

    /// 語の間に空白がない文字列には一致しない
    func test_ranges_spaceRequiresWhitespace() {
        XCTAssertEqual(found("foo bar", in: "foobar"), [])
    }

    func test_ranges_regexCharactersAreLiteral() {
        XCTAssertEqual(found("a.b (c)", in: "a.b (c) axb c"), ["a.b (c)"])
    }

    func test_ranges_emptyOrBlankQuery_findsNothing() {
        XCTAssertEqual(found("", in: "text"), [])
        XCTAssertEqual(found("  ", in: "a  b"), [])
    }

    func test_ranges_japaneseAndEmoji_useUTF16Ranges() {
        let text = "😀 検索 と 検索"
        let ranges = EditorSearchController.ranges(of: "検索", in: text)
        XCTAssertEqual(ranges.map(\.location), [3, 8])
    }

    func test_indexAtOrAfter_wrapsToFirst() {
        let matches = [NSRange(location: 2, length: 1), NSRange(location: 10, length: 1)]
        XCTAssertEqual(EditorSearchController.index(atOrAfter: 0, in: matches), 0)
        XCTAssertEqual(EditorSearchController.index(atOrAfter: 3, in: matches), 1)
        XCTAssertEqual(EditorSearchController.index(atOrAfter: 11, in: matches), 0)
    }
}

// MARK: - エディタでの検索・移動・置換

@MainActor
final class EditorSearchControllerTests: XCTestCase {
    private var window: NSWindow!
    private var textView: NSTextView!
    private var sut: EditorSearchController!

    override func setUp() async throws {
        // アプリのエディタと同じ作り方（TextKit 1）にする
        let (scrollView, editorTextView) = MarkdownEditorView.makeTextView()
        textView = editorTextView
        // 取り消しはウィンドウの UndoManager に積まれる
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

    private var selectedText: String {
        (textView.string as NSString).substring(with: textView.selectedRange())
    }

    func test_search_selecting_picksFirstMatchAtOrAfterCaret() {
        // Arrange
        textView.string = "one cat, two cat, three cat"
        textView.setSelectedRange(NSRange(location: 6, length: 0))

        // Act
        sut.search("cat", selecting: true)

        // Assert: 2つ目の cat（位置 13）を選ぶ
        XCTAssertEqual(sut.status, RenderViewModel.SearchStatus(current: 2, total: 3))
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 13, length: 3))
    }

    /// 対象でないときは強調だけ。件数を出さず、選択も動かさない
    func test_search_notSelecting_leavesSelectionAndHasNoStatus() {
        // Arrange
        textView.string = "cat cat"
        textView.setSelectedRange(NSRange(location: 1, length: 0))

        // Act
        sut.search("cat", selecting: false)

        // Assert
        XCTAssertNil(sut.status)
        XCTAssertEqual(sut.matches.count, 2)
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 1, length: 0))
    }

    func test_search_noMatch_reportsZero() {
        textView.string = "dog"

        sut.search("cat", selecting: true)

        XCTAssertEqual(sut.status, RenderViewModel.SearchStatus(current: 0, total: 0))
    }

    func test_findNextAndPrevious_wrapAround() {
        // Arrange
        textView.string = "a x a x a"
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        sut.search("a", selecting: true)

        // Act & Assert
        sut.findNext()
        XCTAssertEqual(sut.status?.current, 2)
        sut.findNext()
        XCTAssertEqual(sut.status?.current, 3)
        sut.findNext()
        XCTAssertEqual(sut.status?.current, 1)
        sut.findPrevious()
        XCTAssertEqual(sut.status?.current, 3)
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 8, length: 1))
    }

    /// 本文が変わったら数え直す。選んでいた番号は保つ
    func test_refresh_afterEdit_recountsAndKeepsIndex() {
        // Arrange
        textView.string = "cat cat cat"
        textView.setSelectedRange(NSRange(location: 4, length: 0))
        sut.search("cat", selecting: true)

        // Act
        textView.string = "cat cat cat cat"
        sut.refresh()

        // Assert
        XCTAssertEqual(sut.status, RenderViewModel.SearchStatus(current: 2, total: 4))
    }

    private func background(at location: Int) -> NSColor? {
        textView.layoutManager?.temporaryAttribute(.backgroundColor, atCharacterIndex: location, effectiveRange: nil)
            as? NSColor
    }

    /// 一致はすべて強調し、選んでいる一致だけ色を変える。閉じたら消す
    func test_highlights_everyMatchAndCurrentDiffers_clearedOnClear() {
        // Arrange
        textView.string = "cat dog cat"
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        // Act
        sut.search("cat", selecting: true)

        // Assert
        let current = background(at: 0)
        let other = background(at: 8)
        XCTAssertNotNil(current)
        XCTAssertNotNil(other)
        XCTAssertNotEqual(current, other)
        XCTAssertNil(background(at: 4))
        sut.clear()
        XCTAssertNil(background(at: 0))
        XCTAssertNil(background(at: 8))
    }

    /// 対象でないときも、一致には色を付ける
    func test_highlights_notSelecting_stillMarksMatches() {
        textView.string = "cat cat"

        sut.search("cat", selecting: false)

        XCTAssertNotNil(background(at: 0))
        XCTAssertNotNil(background(at: 4))
    }

    func test_clear_dropsMatchesAndStatus() {
        textView.string = "cat"
        sut.search("cat", selecting: true)

        sut.clear()

        XCTAssertNil(sut.status)
        XCTAssertTrue(sut.matches.isEmpty)
    }

    func test_replaceCurrent_replacesSelectedMatchAndMovesToNext() {
        // Arrange
        textView.string = "cat cat cat"
        textView.setSelectedRange(NSRange(location: 4, length: 0))
        sut.search("cat", selecting: true)

        // Act
        sut.replaceCurrent(with: "dog")

        // Assert: 2つ目を置き換え、次（もとの3つ目）を選ぶ
        XCTAssertEqual(textView.string, "cat dog cat")
        XCTAssertEqual(sut.status, RenderViewModel.SearchStatus(current: 2, total: 2))
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 8, length: 3))
    }

    func test_replaceCurrent_canBeUndone() throws {
        // Arrange
        textView.string = "cat cat"
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        sut.search("cat", selecting: true)
        let undoManager = try XCTUnwrap(textView.undoManager)

        // Act
        sut.replaceCurrent(with: "dog")
        undoManager.undo()

        // Assert
        XCTAssertEqual(textView.string, "cat cat")
    }

    func test_replaceAll_replacesEveryMatchAndUndoesInOneStep() throws {
        // Arrange
        textView.string = "Cat cat\ncAt"
        sut.search("cat", selecting: true)
        let undoManager = try XCTUnwrap(textView.undoManager)

        // Act
        let count = sut.replaceAll(with: "dog")

        // Assert
        XCTAssertEqual(count, 3)
        XCTAssertEqual(textView.string, "dog dog\ndog")
        XCTAssertEqual(sut.status, RenderViewModel.SearchStatus(current: 0, total: 0))
        undoManager.undo()
        XCTAssertEqual(textView.string, "Cat cat\ncAt")
    }

    /// 置換で本文が変わったことを、エディタの delegate（DocumentViewModel への反映）に知らせる
    func test_replaceAll_notifiesTextDidChange() {
        // Arrange
        textView.string = "cat"
        sut.search("cat", selecting: true)
        let expectation = expectation(forNotification: NSText.didChangeNotification, object: textView)

        // Act
        sut.replaceAll(with: "dog")

        // Assert
        wait(for: [expectation], timeout: 1)
    }

    /// 置き換え後の文字列に検索語が含まれていても、置き換えを繰り返さない
    func test_replaceAll_replacementContainingQuery_replacesOnce() {
        textView.string = "a a"
        sut.search("a", selecting: true)

        sut.replaceAll(with: "aa")

        XCTAssertEqual(textView.string, "aa aa")
    }
}

// MARK: - ⌘F の対象

final class SearchCommandTargetTests: XCTestCase {
    func test_target_editorHasFocus_isEditor() {
        XCTAssertEqual(
            SearchCommand.target(editorHasFocus: true, searchFieldHasFocus: false, current: .preview),
            .editor
        )
    }

    /// 検索欄に入力があるとき（開いたまま押し直したとき）は対象を変えない
    func test_target_searchFieldHasFocus_keepsCurrent() {
        XCTAssertEqual(
            SearchCommand.target(editorHasFocus: false, searchFieldHasFocus: true, current: .editor),
            .editor
        )
    }

    func test_target_elsewhere_isPreview() {
        XCTAssertEqual(
            SearchCommand.target(editorHasFocus: false, searchFieldHasFocus: false, current: .editor),
            .preview
        )
    }
}

// MARK: - エディタの入力を DocumentViewModel に反映する

@MainActor
final class MarkdownEditorCoordinatorTests: XCTestCase {
    func test_textChanged_updatesDocumentAndRecountsSearch() {
        // Arrange
        let documentVM = DocumentViewModel()
        let editorSearch = EditorSearchController()
        let textView = NSTextView()
        editorSearch.textView = textView
        textView.string = "cat"
        editorSearch.search("cat", selecting: true)
        let coordinator = MarkdownEditorView.Coordinator(documentVM: documentVM, editorSearch: editorSearch)

        // Act
        textView.string = "cat cat"
        coordinator.textChanged(in: textView)

        // Assert
        XCTAssertEqual(documentVM.text, "cat cat")
        XCTAssertTrue(documentVM.isDirty)
        XCTAssertEqual(editorSearch.status?.total, 2)
    }

    /// 置換を取り消したときも、取り消した後の本文を DocumentViewModel に反映する
    /// （delegate の textDidChange は取り消しでは呼ばれない）
    func test_undoReplace_updatesDocument() async throws {
        // Arrange
        let (scrollView, textView) = MarkdownEditorView.makeTextView()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = scrollView
        defer { window.close() }
        let documentVM = DocumentViewModel()
        let editorSearch = EditorSearchController()
        let coordinator = MarkdownEditorView.Coordinator(documentVM: documentVM, editorSearch: editorSearch)
        textView.string = "cat cat"
        coordinator.observe(textView)
        editorSearch.textView = textView
        editorSearch.search("cat", selecting: true)
        let undoManager = try XCTUnwrap(textView.undoManager)

        // Act
        editorSearch.replaceCurrent(with: "dog")
        try await Task.sleep(nanoseconds: 50_000_000)
        let afterReplace = documentVM.text
        undoManager.undo()
        try await Task.sleep(nanoseconds: 50_000_000)

        // Assert
        XCTAssertEqual(afterReplace, "dog cat")
        XCTAssertEqual(documentVM.text, "cat cat")
        withExtendedLifetime(coordinator) {}
    }
}
