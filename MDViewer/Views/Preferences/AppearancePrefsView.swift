import SwiftUI

struct AppearancePrefsView: View {
    @AppStorage("selectedThemeId") private var selectedThemeId: String = MarkdownTheme.githubLight.id
    @AppStorage("fontSize") private var fontSize: Double = 16
    @AppStorage("codeFont") private var codeFont: String = "Menlo"

    private let codeFonts = ["Menlo", "SF Mono", "JetBrains Mono", "Courier New"]

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
                    Slider(value: $fontSize, in: 10...32, step: 1)
                    Text("\(Int(fontSize))pt")
                        .frame(width: 36, alignment: .trailing)
                }

                Picker("Code Font", selection: $codeFont) {
                    ForEach(codeFonts, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .padding()
    }
}
