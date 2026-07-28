import SwiftUI

struct MarkdownEditorView: View {
    @ObservedObject var documentVM: DocumentViewModel

    var body: some View {
        TextEditor(text: Binding(
            get: { documentVM.text },
            set: { documentVM.updateText($0) }
        ))
        .font(.system(.body, design: .monospaced))
    }
}
