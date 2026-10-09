import SwiftUI

struct AppearancePrefsView: View {
    @AppStorage("selectedThemeId") private var selectedThemeId: String = MarkdownTheme.githubLight.id
    @AppStorage("fontSize") private var fontSize: Double = 16
    @AppStorage(PreviewFont.bodyKey) private var bodyFont: String = ""
    @AppStorage(PreviewFont.headingKey) private var headingFont: String = ""
    @AppStorage(PreviewFont.codeKey) private var codeFont: String = PreviewFont.defaultCodeFont

    private let codeFonts = ["Menlo", "SF Mono", "JetBrains Mono", "Courier New"]
    private let fontFamilies = NSFontManager.shared.availableFontFamilies.sorted {
        $0.localizedStandardCompare($1) == .orderedAscending
    }

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Theme", selection: $selectedThemeId) {
                    ForEach(MarkdownTheme.all) { theme in
                        Text(theme.displayName).tag(theme.id)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Font") {
                HStack {
                    Text("Size")
                    Slider(value: $fontSize, in: 10 ... 32, step: 1)
                    Text("\(Int(fontSize))pt")
                        .frame(width: 36, alignment: .trailing)
                }

                Picker("Body Font", selection: $bodyFont) {
                    Text("System").tag("")
                    Divider()
                    ForEach(fontFamilies, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .pickerStyle(.menu)

                Picker("Heading Font", selection: $headingFont) {
                    Text("Same as Body").tag("")
                    Divider()
                    ForEach(fontFamilies, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .pickerStyle(.menu)

                Picker("Code Font", selection: $codeFont) {
                    ForEach(codeFonts, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .padding()
        .onChange(of: [bodyFont, headingFont, codeFont]) { _ in
            NotificationCenter.default.post(name: .previewFontsChanged, object: nil)
        }
    }
}
