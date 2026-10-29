import SwiftUI

struct GeneralPrefsView: View {
    @AppStorage(DocumentViewModel.restoreOnLaunchKey) private var restoreLastFile: Bool = true
    @AppStorage(DocumentViewModel.autoReloadKey) private var autoReload: Bool = true
    @AppStorage("pdfPageSize") private var pdfPageSizeRaw: String = PDFPageSize.a4.rawValue
    @AppStorage(RenderViewModel.mathBracketDelimitersKey) private var mathBracketDelimiters: Bool = false

    var body: some View {
        Form {
            Section {
                Toggle("Reopen documents from last time on launch", isOn: $restoreLastFile)
                Toggle("Auto-reload file when changed on disk", isOn: $autoReload)
            }

            Section("PDF") {
                Picker("Page Size", selection: $pdfPageSizeRaw) {
                    ForEach(PDFPageSize.allCases, id: \.rawValue) { size in
                        Text(size.displayName).tag(size.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                // 幅を絞るとラベルまで押し縮められ、macOS 27 では「Page Size」が折り返される（#15）
                .fixedSize()
                .onChange(of: pdfPageSizeRaw) { newValue in
                    NotificationCenter.default.post(name: .pdfPageSizeChanged, object: newValue)
                }
            }

            // 文言はローカライズした String で渡す。LocalizedStringKey のままだと Markdown として
            // 読まれ、\( や \[ のバックスラッシュがエスケープとして消える
            Section("Math") {
                Toggle(isOn: $mathBracketDelimiters) {
                    Text(String(localized: "Treat \\( \\) and \\[ \\] as math delimiters"))
                }
                .onChange(of: mathBracketDelimiters) { _ in
                    NotificationCenter.default.post(name: .mathOptionsChanged, object: nil)
                }
                Text(String(localized: "When on, paired \\( \\) and \\[ \\] are shown as math, not brackets."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}
