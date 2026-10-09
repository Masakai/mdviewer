import Foundation

/// プレビューの本文・見出し・コードのフォント設定。
/// 設定値はフォントファミリー名で、空文字は既定（本文はシステムフォント、見出しは本文と同じ）を表す。
enum PreviewFont {
    static let bodyKey = "bodyFont"
    static let headingKey = "headingFont"
    static let codeKey = "codeFont"
    static let defaultCodeFont = "Menlo"

    /// mdviewer-base.css の既定値と同じ。選んだフォントに無い文字（日本語など）もこれで表示する。
    static let bodyFallback = "-apple-system, BlinkMacSystemFont, \"Segoe UI\", Helvetica, Arial, sans-serif"
    static let codeFallback = "Menlo, \"SF Mono\", \"JetBrains Mono\", monospace"

    static func bodyCSS(_ family: String) -> String {
        family.isEmpty ? bodyFallback : "\(quoted(family)), \(bodyFallback)"
    }

    static func headingCSS(_ family: String) -> String {
        family.isEmpty ? "var(--body-font)" : "\(quoted(family)), \(bodyFallback)"
    }

    static func codeCSS(_ family: String) -> String {
        family.isEmpty ? codeFallback : "\(quoted(family)), \(codeFallback)"
    }

    /// フォントを切り替える JS。値は JSON で渡し、フォント名に引用符などが含まれても壊れないようにする。
    static func setFontsScript(body: String, heading: String, code: String) -> String {
        let fonts = ["body": bodyCSS(body), "heading": headingCSS(heading), "code": codeCSS(code)]
        guard let data = try? JSONSerialization.data(withJSONObject: fonts, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8)
        else { return "" }
        return "MDViewer.setFonts(\(json))"
    }

    /// 保存されている設定から JS を作る。
    static func setFontsScript(defaults: UserDefaults = .standard) -> String {
        setFontsScript(
            body: defaults.string(forKey: bodyKey) ?? "",
            heading: defaults.string(forKey: headingKey) ?? "",
            code: defaults.string(forKey: codeKey) ?? defaultCodeFont
        )
    }

    private static func quoted(_ family: String) -> String {
        let escaped = family
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
