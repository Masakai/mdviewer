import XCTest
@testable import MDViewer

final class MarkdownEditorViewTests: XCTestCase {
    // MARK: - エディタの文字サイズはプレビューの本文と同じポイント数

    func test_editorFontSize_matchesPreviewFontSize() {
        XCTAssertEqual(MarkdownEditorView.editorFontSize(forPreviewFontSize: 16), 16)
        XCTAssertEqual(MarkdownEditorView.editorFontSize(forPreviewFontSize: 10), 10)
        XCTAssertEqual(MarkdownEditorView.editorFontSize(forPreviewFontSize: 32), 32)
    }

    /// プレビューには Int に切り捨てた値を渡しているので、端数のある値でも同じ大きさにする
    func test_editorFontSize_fractionalValue_truncatedLikePreview() {
        XCTAssertEqual(MarkdownEditorView.editorFontSize(forPreviewFontSize: 17.9), 17)
    }
}
