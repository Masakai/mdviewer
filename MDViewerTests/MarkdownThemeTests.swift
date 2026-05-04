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
}
