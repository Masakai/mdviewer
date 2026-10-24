import SwiftUI

struct MarkdownEditorView: View {
    @ObservedObject var documentVM: DocumentViewModel
    /// プレビューの本文の文字サイズ（RenderViewModel.fontSize）
    let previewFontSize: Double

    var body: some View {
        // サイズだけを差し替える。TextEditor を作り直すとカーソル位置やスクロール位置が失われる
        TextEditor(text: Binding(
            get: { documentVM.text },
            set: { documentVM.updateText($0) }
        ))
        .font(.system(size: Self.editorFontSize(forPreviewFontSize: previewFontSize), design: .monospaced))
    }

    /// エディタの文字サイズ。プレビューの本文と同じポイント数にする。
    /// プレビューには整数に切り捨てた値を渡している（MDViewer.setFontSize）ので、それに揃える。
    static func editorFontSize(forPreviewFontSize size: Double) -> CGFloat {
        CGFloat(Int(size))
    }
}
