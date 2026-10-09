import SwiftUI

struct GeneralPrefsView: View {
    @AppStorage(DocumentViewModel.restoreOnLaunchKey) private var restoreLastFile: Bool = true
    @AppStorage(DocumentViewModel.autoReloadKey) private var autoReload: Bool = true
    @AppStorage("pdfPageSize") private var pdfPageSizeRaw: String = PDFPageSize.a4.rawValue

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
        }
        .padding()
    }
}
