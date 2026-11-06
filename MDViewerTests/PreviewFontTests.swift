import XCTest
@testable import MDViewer

final class PreviewFontTests: XCTestCase {
    // MARK: - CSS の組み立て

    func test_bodyCSS_empty_usesSystemFontStack() {
        XCTAssertEqual(PreviewFont.bodyCSS(""), PreviewFont.bodyFallback)
    }

    func test_bodyCSS_family_putsItFirstAndKeepsFallback() {
        XCTAssertEqual(PreviewFont.bodyCSS("Georgia"), "\"Georgia\", \(PreviewFont.bodyFallback)")
    }

    func test_headingCSS_empty_followsBodyFont() {
        XCTAssertEqual(PreviewFont.headingCSS(""), "var(--body-font)")
    }

    func test_headingCSS_family_putsItFirstAndKeepsFallback() {
        XCTAssertEqual(PreviewFont.headingCSS("Avenir Next"), "\"Avenir Next\", \(PreviewFont.bodyFallback)")
    }

    func test_codeCSS_family_keepsMonospaceFallback() {
        XCTAssertEqual(PreviewFont.codeCSS("SF Mono"), "\"SF Mono\", \(PreviewFont.codeFallback)")
    }

    func test_css_escapesQuotesInFamilyName() {
        XCTAssertEqual(PreviewFont.bodyCSS("A\"B"), "\"A\\\"B\", \(PreviewFont.bodyFallback)")
    }

    // MARK: - コードフォントの選択肢

    func test_codeFontChoices_putsMonospacedFirstAndKeepsOrder() {
        let choices = PreviewFont.codeFontChoices(
            families: ["Avenir", "Courier New", "Georgia", "Menlo"],
            monospaced: ["Menlo", "Courier New"],
            current: "Menlo"
        )
        XCTAssertEqual(choices.monospaced, ["Courier New", "Menlo"])
        XCTAssertEqual(choices.others, ["Avenir", "Georgia"])
        XCTAssertNil(choices.unavailable)
    }

    func test_codeFontChoices_nonMonospacedSelection_isNotUnavailable() {
        let choices = PreviewFont.codeFontChoices(
            families: ["Georgia", "Menlo"], monospaced: ["Menlo"], current: "Georgia"
        )
        XCTAssertNil(choices.unavailable)
    }

    func test_codeFontChoices_notInstalledSelection_isReportedAsUnavailable() {
        let choices = PreviewFont.codeFontChoices(
            families: ["Menlo"], monospaced: ["Menlo"], current: "JetBrains Mono"
        )
        XCTAssertEqual(choices.unavailable, "JetBrains Mono")
        XCTAssertEqual(choices.monospaced, ["Menlo"])
    }

    // MARK: - JS

    func test_setFontsScript_passesAllThreeStacksAsJSON() throws {
        let script = PreviewFont.setFontsScript(body: "Georgia", heading: "", code: "Menlo")
        XCTAssertTrue(script.hasPrefix("MDViewer.setFonts("))
        XCTAssertTrue(script.hasSuffix(")"))

        let json = String(script.dropFirst("MDViewer.setFonts(".count).dropLast())
        let fonts = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: String])
        XCTAssertEqual(fonts["body"], PreviewFont.bodyCSS("Georgia"))
        XCTAssertEqual(fonts["heading"], "var(--body-font)")
        XCTAssertEqual(fonts["code"], PreviewFont.codeCSS("Menlo"))
    }

    func test_setFontsScript_noSavedSettings_usesDefaults() throws {
        let suiteName = "PreviewFontTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(
            PreviewFont.setFontsScript(defaults: defaults),
            PreviewFont.setFontsScript(body: "", heading: "", code: PreviewFont.defaultCodeFont)
        )
    }
}
