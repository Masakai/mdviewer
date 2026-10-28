import AppKit
import SwiftUI

/// Markdown のエディタ。検索で選択・スクロール・強調・置換を行うため、TextEditor ではなく
/// NSTextView を直接使う。入力まわりの設定は TextEditor と同じにしている（自動置換や
/// スペルチェックはシステム設定に従う）。
struct MarkdownEditorView: NSViewRepresentable {
    @ObservedObject var documentVM: DocumentViewModel
    /// プレビューの本文の文字サイズ（RenderViewModel.fontSize）
    let previewFontSize: Double
    let editorSearch: EditorSearchController

    func makeCoordinator() -> Coordinator {
        Coordinator(documentVM: documentVM, editorSearch: editorSearch)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let (scrollView, textView) = Self.makeTextView()
        textView.font = Self.font(forPreviewFontSize: previewFontSize)
        textView.string = documentVM.text
        context.coordinator.observe(textView)
        editorSearch.textView = textView
        return scrollView
    }

    /// エディタの NSTextView。検索の強調に NSLayoutManager の一時属性を使うので、TextKit 1 で作る
    /// （TextKit 2 の表示属性は、付けても描き直されない行が残る）。
    static func makeTextView() -> (NSScrollView, NSTextView) {
        let textView = NSTextView(usingTextLayoutManager: false)
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.documentView = textView

        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFontPanel = false
        textView.usesRuler = false
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .textColor
        return (scrollView, textView)
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.documentVM = documentVM

        // サイズだけを差し替える。作り直すとカーソル位置やスクロール位置が失われる
        let font = Self.font(forPreviewFontSize: previewFontSize)
        if textView.font != font {
            textView.font = font
        }

        // 再読み込みなど、エディタの外で本文が変わったときだけ入れ替える。変換中の文字が
        // あるときに入れ替えると、日本語入力が確定前に壊れる
        if !textView.hasMarkedText(), textView.string != documentVM.text {
            let selection = textView.selectedRange()
            textView.string = documentVM.text
            let length = (textView.string as NSString).length
            textView.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
            editorSearch.refresh()
        }
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        if coordinator.editorSearch.textView === scrollView.documentView {
            coordinator.editorSearch.textView = nil
        }
    }

    private static func font(forPreviewFontSize size: Double) -> NSFont {
        .monospacedSystemFont(ofSize: editorFontSize(forPreviewFontSize: size), weight: .regular)
    }

    /// エディタの文字サイズ。プレビューの本文と同じポイント数にする。
    /// プレビューには整数に切り捨てた値を渡している（MDViewer.setFontSize）ので、それに揃える。
    static func editorFontSize(forPreviewFontSize size: Double) -> CGFloat {
        CGFloat(Int(size))
    }

    final class Coordinator: NSObject {
        var documentVM: DocumentViewModel
        let editorSearch: EditorSearchController
        private var observer: NSObjectProtocol?

        init(documentVM: DocumentViewModel, editorSearch: EditorSearchController) {
            self.documentVM = documentVM
            self.editorSearch = editorSearch
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }

        /// 本文の変化はテキストストレージの編集で受ける。delegate の textDidChange は、検索の置換を
        /// 取り消したときには呼ばれないので、それだけではプレビューと保存する内容が古いまま残る。
        /// 編集の途中で強調を付け直さないよう、反映は編集が終わってから行う。
        func observe(_ textView: NSTextView) {
            observer = NotificationCenter.default.addObserver(
                forName: NSTextStorage.didProcessEditingNotification,
                object: textView.textStorage,
                queue: nil
            ) { [weak self, weak textView] notification in
                guard let storage = notification.object as? NSTextStorage,
                      storage.editedMask.contains(.editedCharacters)
                else { return }
                DispatchQueue.main.async {
                    guard let self, let textView else { return }
                    MainActor.assumeIsolated { self.textChanged(in: textView) }
                }
            }
        }

        @MainActor
        func textChanged(in textView: NSTextView) {
            documentVM.updateText(textView.string)
            editorSearch.refresh()
        }
    }
}
