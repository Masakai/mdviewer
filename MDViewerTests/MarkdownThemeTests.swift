import XCTest
@testable import MDViewer

final class MarkdownThemeTests: XCTestCase {
    // MARK: - Theme list completeness

    func test_allThemes_isNotEmpty() {
        XCTAssertFalse(MarkdownTheme.all.isEmpty)
    }

    func test_allThemes_containsSixThemes() {
        XCTAssertEqual(MarkdownTheme.all.count, 6)
    }

    // MARK: - Static shortcuts

    func test_githubLight_idMatchesExpected() {
        XCTAssertEqual(MarkdownTheme.githubLight.id, "github-light")
    }

    func test_githubDark_idMatchesExpected() {
        XCTAssertEqual(MarkdownTheme.githubDark.id, "github-dark")
    }

    func test_githubLight_isNotDark() {
        XCTAssertFalse(MarkdownTheme.githubLight.isDark)
    }

    func test_githubDark_isDark() {
        XCTAssertTrue(MarkdownTheme.githubDark.isDark)
    }

    // MARK: - ID uniqueness

    func test_allThemes_haveUniqueIDs() {
        let ids = MarkdownTheme.all.map(\.id)
        let uniqueIds = Set(ids)
        XCTAssertEqual(ids.count, uniqueIds.count, "Duplicate theme IDs found")
    }

    // MARK: - ID and cssFileName consistency

    func test_allThemes_idMatchesCSSFileName() {
        for theme in MarkdownTheme.all {
            XCTAssertEqual(
                theme.id,
                theme.cssFileName,
                "Theme '\(theme.displayName)': id '\(theme.id)' != cssFileName '\(theme.cssFileName)'"
            )
        }
    }

    // MARK: - Bundled CSS

    /// 一覧に出しているテーマは、すべて CSS を同梱していなければ選んでも効かない（#14）
    func test_allThemes_haveBundledCSS() throws {
        let themesDirectory = try XCTUnwrap(HTMLBuilder.webResourcesDirectory()).appendingPathComponent("themes")
        for theme in MarkdownTheme.all {
            let css = themesDirectory.appendingPathComponent("\(theme.cssFileName).css")
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: css.path),
                "Theme '\(theme.displayName)' has no CSS at \(css.path)"
            )
        }
    }

    // MARK: - No empty fields

    func test_allThemes_haveNonEmptyID() {
        for theme in MarkdownTheme.all {
            XCTAssertFalse(theme.id.isEmpty, "Theme has empty id: \(theme)")
        }
    }

    func test_allThemes_haveNonEmptyDisplayName() {
        for theme in MarkdownTheme.all {
            XCTAssertFalse(theme.displayName.isEmpty, "Theme has empty displayName: \(theme)")
        }
    }

    func test_allThemes_haveNonEmptyCSSFileName() {
        for theme in MarkdownTheme.all {
            XCTAssertFalse(theme.cssFileName.isEmpty, "Theme has empty cssFileName: \(theme)")
        }
    }

    // MARK: - Dark/light categorization

    func test_allThemes_darkThemesCount() {
        let darkThemes = MarkdownTheme.all.filter(\.isDark)
        // github-dark, solarized-dark, dracula, nord = 4 dark themes
        XCTAssertEqual(darkThemes.count, 4)
    }

    func test_allThemes_lightThemesCount() {
        let lightThemes = MarkdownTheme.all.filter { !$0.isDark }
        // github-light, solarized-light = 2 light themes
        XCTAssertEqual(lightThemes.count, 2)
    }

    // MARK: - Specific theme properties

    func test_draculaTheme_isDark() {
        guard let dracula = MarkdownTheme.all.first(where: { $0.id == "dracula" }) else {
            XCTFail("Dracula theme not found")
            return
        }
        XCTAssertTrue(dracula.isDark)
    }

    func test_nordTheme_isDark() {
        guard let nord = MarkdownTheme.all.first(where: { $0.id == "nord" }) else {
            XCTFail("Nord theme not found")
            return
        }
        XCTAssertTrue(nord.isDark)
    }

    func test_solarizedLightTheme_isNotDark() {
        guard let theme = MarkdownTheme.all.first(where: { $0.id == "solarized-light" }) else {
            XCTFail("Solarized Light theme not found")
            return
        }
        XCTAssertFalse(theme.isDark)
    }

    func test_solarizedDarkTheme_isDark() {
        guard let theme = MarkdownTheme.all.first(where: { $0.id == "solarized-dark" }) else {
            XCTFail("Solarized Dark theme not found")
            return
        }
        XCTAssertTrue(theme.isDark)
    }

    // MARK: - Identifiable / Hashable / Equatable

    func test_githubLight_equalsItself() {
        XCTAssertEqual(MarkdownTheme.githubLight, MarkdownTheme.githubLight)
    }

    func test_githubLight_doesNotEqualGithubDark() {
        XCTAssertNotEqual(MarkdownTheme.githubLight, MarkdownTheme.githubDark)
    }

    func test_themes_areUsableInSet() {
        let set: Set<MarkdownTheme> = Set(MarkdownTheme.all)
        XCTAssertEqual(set.count, MarkdownTheme.all.count)
    }

    // MARK: - PDFPageSize

    func test_pdfPageSize_a4_displayName() {
        XCTAssertEqual(PDFPageSize.a4.displayName, "A4")
    }

    func test_pdfPageSize_letter_displayName() {
        XCTAssertEqual(PDFPageSize.letter.displayName, "Letter")
    }

    func test_pdfPageSize_a3_displayName() {
        XCTAssertEqual(PDFPageSize.a3.displayName, "A3")
    }

    func test_pdfPageSize_a4_cssSize() {
        XCTAssertEqual(PDFPageSize.a4.cssSize, "210mm 297mm")
    }

    func test_pdfPageSize_letter_cssSize() {
        XCTAssertEqual(PDFPageSize.letter.cssSize, "8.5in 11in")
    }

    func test_pdfPageSize_a3_cssSize() {
        XCTAssertEqual(PDFPageSize.a3.cssSize, "297mm 420mm")
    }

    func test_pdfPageSize_a4_pointSize_width() {
        XCTAssertEqual(PDFPageSize.a4.pointSize.width, 595.28, accuracy: 0.01)
    }

    func test_pdfPageSize_a4_pointSize_height() {
        XCTAssertEqual(PDFPageSize.a4.pointSize.height, 841.89, accuracy: 0.01)
    }

    func test_pdfPageSize_allCases_countIsThree() {
        XCTAssertEqual(PDFPageSize.allCases.count, 3)
    }

    // MARK: - backgroundHex / slots

    func test_backgroundHex_matchesCSSBgColor_forEveryTheme() throws {
        let themesDirectory = try XCTUnwrap(HTMLBuilder.webResourcesDirectory()).appendingPathComponent("themes")
        let regex = try NSRegularExpression(pattern: "--bg-color:\\s*(#[0-9a-fA-F]{6})")
        for theme in MarkdownTheme.all {
            let css = try String(contentsOf: themesDirectory.appendingPathComponent("\(theme.cssFileName).css"))
            let match = try XCTUnwrap(regex.firstMatch(in: css, range: NSRange(css.startIndex..., in: css)))
            let hex = String(css[try XCTUnwrap(Range(match.range(at: 1), in: css))])
            XCTAssertEqual(theme.backgroundHex.lowercased(), hex.lowercased(), theme.id)
        }
    }

    func test_lightAndDarkThemes_partitionAll() {
        XCTAssertTrue(MarkdownTheme.lightThemes.allSatisfy { !$0.isDark })
        XCTAssertTrue(MarkdownTheme.darkThemes.allSatisfy(\.isDark))
        XCTAssertEqual(MarkdownTheme.lightThemes.count, 2)
        XCTAssertEqual(MarkdownTheme.darkThemes.count, 4)
    }

    // MARK: - ThemePreference

    private func withSettings(_ body: (UserDefaults) throws -> Void) throws {
        let suiteName = "MarkdownThemeTests-\(UUID().uuidString)"
        let settings = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { settings.removePersistentDomain(forName: suiteName) }
        try body(settings)
    }

    func test_load_nothingSaved_followOnWithGitHubPair() throws {
        try withSettings { settings in
            let p = ThemePreference.load(from: settings)
            XCTAssertTrue(p.followsSystem)
            XCTAssertEqual(p.light, .githubLight)
            XCTAssertEqual(p.dark, .githubDark)
            XCTAssertEqual(p.fixed, .githubLight)
        }
    }

    func test_load_legacyGitHubDark_followOn() throws {
        try withSettings { settings in
            settings.set("github-dark", forKey: ThemePreference.fixedKey)
            let p = ThemePreference.load(from: settings)
            XCTAssertTrue(p.followsSystem)
            XCTAssertEqual(p.fixed, .githubDark)
        }
    }

    func test_load_legacyNord_followOffAndFixedNord() throws {
        try withSettings { settings in
            settings.set("nord", forKey: ThemePreference.fixedKey)
            let p = ThemePreference.load(from: settings)
            XCTAssertFalse(p.followsSystem)
            XCTAssertEqual(p.fixed.id, "nord")
            XCTAssertEqual(p.dark.id, "nord")
            XCTAssertEqual(p.light, .githubLight)
        }
    }

    func test_load_legacySolarizedLight_fillsLightSlot() throws {
        try withSettings { settings in
            settings.set("solarized-light", forKey: ThemePreference.fixedKey)
            let p = ThemePreference.load(from: settings)
            XCTAssertFalse(p.followsSystem)
            XCTAssertEqual(p.light.id, "solarized-light")
            XCTAssertEqual(p.dark, .githubDark)
        }
    }

    func test_load_explicitKeysWinOverLegacy() throws {
        try withSettings { settings in
            settings.set("nord", forKey: ThemePreference.fixedKey)
            settings.set(true, forKey: ThemePreference.followKey)
            settings.set("solarized-light", forKey: ThemePreference.lightKey)
            settings.set("dracula", forKey: ThemePreference.darkKey)
            let p = ThemePreference.load(from: settings)
            XCTAssertTrue(p.followsSystem)
            XCTAssertEqual(p.light.id, "solarized-light")
            XCTAssertEqual(p.dark.id, "dracula")
        }
    }

    func test_load_wrongSlotOrUnknownId_fallsBack() throws {
        try withSettings { settings in
            settings.set("nord", forKey: ThemePreference.lightKey)
            settings.set("nope", forKey: ThemePreference.darkKey)
            let p = ThemePreference.load(from: settings)
            XCTAssertEqual(p.light, .githubLight)
            XCTAssertEqual(p.dark, .githubDark)
        }
    }

    func test_load_followStoredAsStringLaunchArgument() throws {
        try withSettings { settings in
            settings.set("NO", forKey: ThemePreference.followKey)
            XCTAssertFalse(ThemePreference.load(from: settings).followsSystem)
        }
    }

    func test_theme_resolvesBySystemAppearance() {
        var p = ThemePreference(
            followsSystem: true,
            fixed: MarkdownTheme.all[5],
            light: .githubLight,
            dark: MarkdownTheme.all[4]
        )
        XCTAssertEqual(p.theme(systemIsDark: true).id, "dracula")
        XCTAssertEqual(p.theme(systemIsDark: false), .githubLight)
        p.followsSystem = false
        XCTAssertEqual(p.theme(systemIsDark: true).id, "nord")
        XCTAssertEqual(p.theme(systemIsDark: false).id, "nord")
    }

    func test_save_legacyNordChangingFixed_keepsFollowOff() throws {
        try withSettings { settings in
            settings.set("nord", forKey: ThemePreference.fixedKey)
            var p = ThemePreference.load(from: settings)
            p.fixed = .githubDark
            p.save(to: settings)
            let reloaded = ThemePreference.load(from: settings)
            XCTAssertFalse(reloaded.followsSystem)
            XCTAssertEqual(reloaded.fixed, .githubDark)
            XCTAssertEqual(reloaded.dark.id, "nord")
        }
    }

    func test_save_roundTrips() throws {
        try withSettings { settings in
            let p = ThemePreference(
                followsSystem: false,
                fixed: MarkdownTheme.all[3],
                light: MarkdownTheme.all[2],
                dark: MarkdownTheme.all[4]
            )
            p.save(to: settings)
            XCTAssertEqual(ThemePreference.load(from: settings), p)
        }
    }
}
