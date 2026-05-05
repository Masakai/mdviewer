import SwiftUI

struct MainToolbar: ToolbarContent {
    @ObservedObject var documentVM: DocumentViewModel
    @ObservedObject var renderVM: RenderViewModel
    @ObservedObject var exportVM: ExportViewModel

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                documentVM.openFile()
            } label: {
                Label("Open", systemImage: "folder")
            }
            .help("Open Markdown File (⌘O)")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            // Font size controls
            HStack(spacing: 4) {
                Button {
                    renderVM.decreaseFontSize()
                } label: {
                    Image(systemName: "textformat.size.smaller")
                }
                .help("Decrease Font Size (⌘-)")

                Button {
                    renderVM.resetFontSize()
                } label: {
                    Text("\(Int(renderVM.fontSize))")
                        .font(.caption)
                        .frame(minWidth: 24)
                }
                .help("Reset Font Size (⌘0)")

                Button {
                    renderVM.increaseFontSize()
                } label: {
                    Image(systemName: "textformat.size.larger")
                }
                .help("Increase Font Size (⌘+)")
            }

            Divider()

            // Theme picker
            Menu {
                ForEach(MarkdownTheme.all) { theme in
                    Button(theme.displayName) {
                        renderVM.setTheme(theme)
                    }
                }
            } label: {
                Label("Theme", systemImage: "paintpalette")
            }
            .help("Select Theme")

            // Export menu
            Menu {
                Button("Export as PDF…") {
                    if let wv = renderVM.webView {
                        exportVM.exportToPDF(webView: wv, renderVM: renderVM, sourceURL: documentVM.fileURL)
                    }
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])

                Button("Export as HTML…") {
                    if let wv = renderVM.webView {
                        exportVM.exportToHTML(webView: wv, sourceURL: documentVM.fileURL)
                    }
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Divider()

                Button("Print…") {
                    if let wv = renderVM.webView {
                        exportVM.print(webView: wv)
                    }
                }
                .keyboardShortcut("p", modifiers: .command)
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .help("Export or Print")
        }
    }
}
