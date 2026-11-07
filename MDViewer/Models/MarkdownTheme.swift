import Foundation
import SwiftUI

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
    /// Same value as --bg-color in the theme's CSS, used to paint behind the web view.
    let backgroundHex: String

    static let all: [MarkdownTheme] = [
        MarkdownTheme(
            id: "github-light",
            displayName: "GitHub Light",
            cssFileName: "github-light",
            isDark: false,
            backgroundHex: "#ffffff"
        ),
        MarkdownTheme(
            id: "github-dark",
            displayName: "GitHub Dark",
            cssFileName: "github-dark",
            isDark: true,
            backgroundHex: "#0d1117"
        ),
        MarkdownTheme(
            id: "solarized-light",
            displayName: "Solarized Light",
            cssFileName: "solarized-light",
            isDark: false,
            backgroundHex: "#fdf6e3"
        ),
        MarkdownTheme(
            id: "solarized-dark",
            displayName: "Solarized Dark",
            cssFileName: "solarized-dark",
            isDark: true,
            backgroundHex: "#002b36"
        ),
        MarkdownTheme(
            id: "dracula",
            displayName: "Dracula",
            cssFileName: "dracula",
            isDark: true,
            backgroundHex: "#282a36"
        ),
        MarkdownTheme(
            id: "nord",
            displayName: "Nord",
            cssFileName: "nord",
            isDark: true,
            backgroundHex: "#2e3440"
        ),
    ]

    static let githubLight = all[0]
    static let githubDark = all[1]

    static let lightThemes: [MarkdownTheme] = all.filter { !$0.isDark }
    static let darkThemes: [MarkdownTheme] = all.filter(\.isDark)

    static func withId(_ id: String?) -> MarkdownTheme? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }

    /// backgroundHex (#rrggbb) as an sRGB Color.
    var backgroundColor: Color {
        let digits = backgroundHex.drop { $0 == "#" }
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return .clear }
        return Color(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }
}

/// The "Follow System Appearance" setting with the light, dark and fixed themes.
struct ThemePreference: Equatable {
    var followsSystem: Bool
    var fixed: MarkdownTheme
    var light: MarkdownTheme
    var dark: MarkdownTheme

    static let followKey = "followSystemAppearance"
    static let fixedKey = "selectedThemeId"
    static let lightKey = "lightThemeId"
    static let darkKey = "darkThemeId"

    /// Reads the stored values. Missing new keys are derived from the legacy selectedThemeId. Never writes back.
    static func load(from settings: UserDefaults) -> ThemePreference {
        let legacy = MarkdownTheme.withId(settings.string(forKey: fixedKey))

        var light = MarkdownTheme.githubLight
        var dark = MarkdownTheme.githubDark
        if let legacy {
            if legacy.isDark { dark = legacy } else { light = legacy }
        }
        if let saved = MarkdownTheme.withId(settings.string(forKey: lightKey)), !saved.isDark {
            light = saved
        }
        if let saved = MarkdownTheme.withId(settings.string(forKey: darkKey)), saved.isDark {
            dark = saved
        }

        let follows: Bool
        if settings.object(forKey: followKey) == nil {
            // GitHub Light / Dark (or no choice) already followed the appearance: keep doing so.
            follows = legacy == nil || legacy == .githubLight || legacy == .githubDark
        } else {
            follows = settings.bool(forKey: followKey)
        }
        return ThemePreference(followsSystem: follows, fixed: legacy ?? .githubLight, light: light, dark: dark)
    }

    func save(to settings: UserDefaults) {
        settings.set(followsSystem, forKey: Self.followKey)
        settings.set(fixed.id, forKey: Self.fixedKey)
        settings.set(light.id, forKey: Self.lightKey)
        settings.set(dark.id, forKey: Self.darkKey)
    }

    func theme(systemIsDark: Bool) -> MarkdownTheme {
        guard followsSystem else { return fixed }
        return systemIsDark ? dark : light
    }
}
