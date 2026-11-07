import SwiftUI

struct MainToolbar: ToolbarContent {
    @ObservedObject var documentVM: DocumentViewModel
    @ObservedObject var renderVM: RenderViewModel
    @ObservedObject var exportVM: ExportViewModel
    var isEditorMode: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                NotificationCenter.default.post(name: .newFile, object: nil)
            } label: {
                Label("New", systemImage: "doc.badge.plus")
            }
            .help("New Markdown File (⌘N)")
        }

        ToolbarItem(placement: .navigation) {
            Button {
                documentVM.openFile()
            } label: {
                Label("Open", systemImage: "folder")
            }
            .help("Open Markdown File (⌘O)")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            // Editor toggle button
            Button {
                NotificationCenter.default.post(name: .toggleEditorMode, object: nil)
            } label: {
                Label("Editor", systemImage: documentVM.isReadOnly ? "pencil.slash" : "pencil")
            }
            .foregroundColor(isEditorMode ? .accentColor : .primary)
            // 三項演算子に文字列リテラルを並べると String になり翻訳されないので、キーとして渡す
            .help(documentVM.isReadOnly
                ? LocalizedStringKey("Toggle Editor Mode (⌘E). This file is read-only and can't be edited.")
                : LocalizedStringKey("Toggle Editor Mode (⌘E)"))

            // Save button
            Button {
                NotificationCenter.default.post(name: .saveFile, object: nil)
            } label: {
                Label("Save", systemImage: "externaldrive")
            }
            .disabled(!documentVM.isDirty || documentVM.isReadOnly)
            .help("Save (⌘S)")

            Divider()

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
                // Toggles, so the menu shows the current choice with its standard checkmark.
                // Choosing a checked item again does nothing.
                Toggle("Use Settings Theme", isOn: Binding(
                    get: { renderVM.windowThemeOverride == nil },
                    set: { isOn in if isOn { renderVM.useSettingsTheme() } }
                ))

                Divider()

                ForEach(MarkdownTheme.all) { theme in
                    Toggle(theme.displayName, isOn: Binding(
                        get: { renderVM.windowThemeOverride == theme },
                        set: { isOn in if isOn { renderVM.setTheme(theme) } }
                    ))
                }
            } label: {
                Label("Theme", systemImage: "paintpalette")
            }
            .help("Select Theme")

            // Export menu
            // ⇧⌘P・⇧⌘E・⌘P はメニューバーの 書き出し / ファイル メニューに割り当てている
            Menu {
                Button("Export as PDF…") {
                    if let wv = renderVM.webView {
                        exportVM.exportToPDF(webView: wv, sourceURL: documentVM.fileURL)
                    }
                }

                Button("Export as HTML…") {
                    if let wv = renderVM.webView {
                        exportVM.exportToHTML(webView: wv, sourceURL: documentVM.fileURL)
                    }
                }

                Divider()

                Button("Print…") {
                    if let wv = renderVM.webView {
                        exportVM.print(webView: wv)
                    }
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .help("Export or Print")
        }
    }
}
