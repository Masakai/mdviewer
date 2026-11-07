import SwiftUI

struct AppearancePrefsView: View {
    @State private var themePreference = ThemePreference.load(from: .standard)
    @AppStorage("fontSize") private var fontSize: Double = 16
    @AppStorage(PreviewFont.bodyKey) private var bodyFont: String = ""
    @AppStorage(PreviewFont.headingKey) private var headingFont: String = ""
    @AppStorage(PreviewFont.codeKey) private var codeFont: String = PreviewFont.defaultCodeFont

    private let fontFamilies = NSFontManager.shared.availableFontFamilies.sorted {
        $0.localizedStandardCompare($1) == .orderedAscending
    }

    private var codeFontChoices: PreviewFont.CodeFontChoices {
        PreviewFont.codeFontChoices(
            families: fontFamilies,
            monospaced: Self.monospacedFamilies(fontFamilies),
            current: codeFont
        )
    }

    /// すべての書体が等幅のファミリー。Osaka のように等幅の書体（Osaka-Mono）を1つだけ含むファミリーは、
    /// ファミリー名で指定すると等幅でない書体が使われるので除く。
    private static func monospacedFamilies(_ families: [String]) -> Set<String> {
        let manager = NSFontManager.shared
        let fixedPitchNames = Set(manager.availableFontNames(with: .fixedPitchFontMask) ?? [])
        return Set(families.filter { family in
            let names = (manager.availableMembers(ofFontFamily: family) ?? []).compactMap { $0.first as? String }
            return !names.isEmpty && names.allSatisfy(fixedPitchNames.contains)
        })
    }

    var body: some View {
        Form {
            Section("Theme") {
                Toggle("Follow System Appearance", isOn: $themePreference.followsSystem)

                if themePreference.followsSystem {
                    Picker("Light Theme", selection: $themePreference.light) {
                        ForEach(MarkdownTheme.lightThemes) { theme in
                            Text(theme.displayName).tag(theme)
                        }
                    }
                    .pickerStyle(.menu)

                    Picker("Dark Theme", selection: $themePreference.dark) {
                        ForEach(MarkdownTheme.darkThemes) { theme in
                            Text(theme.displayName).tag(theme)
                        }
                    }
                    .pickerStyle(.menu)
                } else {
                    Picker("Theme", selection: $themePreference.fixed) {
                        ForEach(MarkdownTheme.all) { theme in
                            Text(theme.displayName).tag(theme)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            Section("Font") {
                HStack {
                    Text("Size")
                    // onChange(of: fontSize) では送らない。ツールバーや ⌘+ で変えた値も同じキーに保存されるので、
                    // そちらでも通知が出て、そのウィンドウだけのはずの変更が全ウィンドウに広がってしまう
                    Slider(value: Binding(
                        get: { fontSize },
                        set: { newValue in
                            fontSize = newValue
                            NotificationCenter.default.post(name: .previewFontSizeChanged, object: newValue)
                        }
                    ), in: 10 ... 32, step: 1)
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

                let choices = codeFontChoices
                Picker("Code Font", selection: $codeFont) {
                    if let unavailable = choices.unavailable {
                        Text(unavailable).tag(unavailable)
                        Divider()
                    }
                    ForEach(choices.monospaced, id: \.self) { name in
                        Text(name).tag(name)
                    }
                    if !choices.monospaced.isEmpty {
                        Divider()
                    }
                    ForEach(choices.others, id: \.self) { name in
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
        .onAppear {
            themePreference = ThemePreference.load(from: .standard)
        }
        .onChange(of: themePreference) { newValue in
            newValue.save(to: .standard)
            NotificationCenter.default.post(name: .previewThemeChanged, object: nil)
        }
    }
}
