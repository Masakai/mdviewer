import SwiftUI

struct MarkdownEditorView: View {
    @ObservedObject var documentVM: DocumentViewModel

    @State private var editingText: String = ""

    var body: some View {
        TextEditor(text: $editingText)
            .font(.system(.body, design: .monospaced))
            .onAppear {
                editingText = documentVM.text
            }
            .onChange(of: editingText) { _, newValue in
                documentVM.updateText(newValue)
            }
            .onChange(of: documentVM.text) { _, newValue in
                // Sync when file is reloaded externally (e.g., FileWatcher)
                if !documentVM.isDirty {
                    editingText = newValue
                }
            }
    }
}
