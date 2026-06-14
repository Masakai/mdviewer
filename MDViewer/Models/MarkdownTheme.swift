import Foundation

enum PDFPageSize: String, CaseIterable {
    case a4
    case letter
    case a3

    var displayName: String {
        switch self {
        case .a4: "A4"
        case .letter: "Letter"
        case .a3: "A3"
        }
    }

    var cssSize: String {
        switch self {
        case .a4: "210mm 297mm"
        case .letter: "8.5in 11in"
        case .a3: "297mm 420mm"
        }
    }

    /// 1pt = 1/72 inch, 1mm = 72/25.4 pt
    var pointSize: CGSize {
        switch self {
        case .a4: CGSize(width: 595.28, height: 841.89)
        case .letter: CGSize(width: 612.0, height: 792.0)
        case .a3: CGSize(width: 841.89, height: 1190.55)
        }
    }
}

struct MarkdownTheme: Identifiable, Hashable, Codable {
    let id: String
    let displayName: String
    let cssFileName: String
    let isDark: Bool

    static let all: [MarkdownTheme] = [
        MarkdownTheme(id: "github-light", displayName: "GitHub Light", cssFileName: "github-light", isDark: false),
        MarkdownTheme(id: "github-dark", displayName: "GitHub Dark", cssFileName: "github-dark", isDark: true),
        MarkdownTheme(
            id: "solarized-light",
            displayName: "Solarized Light",
            cssFileName: "solarized-light",
            isDark: false
        ),
        MarkdownTheme(id: "solarized-dark", displayName: "Solarized Dark", cssFileName: "solarized-dark", isDark: true),
        MarkdownTheme(id: "dracula", displayName: "Dracula", cssFileName: "dracula", isDark: true),
        MarkdownTheme(id: "nord", displayName: "Nord", cssFileName: "nord", isDark: true),
    ]

    static let githubLight = all[0]
    static let githubDark = all[1]
}
