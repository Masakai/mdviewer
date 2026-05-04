import XCTest
@testable import MDViewer

@MainActor
final class RenderViewModelTests: XCTestCase {

    var sut: RenderViewModel!

    override func setUp() async throws {
        try await super.setUp()
        sut = RenderViewModel()
    }

    override func tearDown() async throws {
        sut = nil
        try await super.tearDown()
    }

    // MARK: - setFontSize clamping

    func test_setFontSize_withinRange_setsExactValue() {
        // Act
        sut.setFontSize(18)

        // Assert
        XCTAssertEqual(sut.fontSize, 18)
    }

    func test_setFontSize_belowMinimum_clampedTo10() {
        // Act
        sut.setFontSize(5)

        // Assert
        XCTAssertEqual(sut.fontSize, 10)
    }

    func test_setFontSize_aboveMaximum_clampedTo32() {
        // Act
        sut.setFontSize(100)

        // Assert
        XCTAssertEqual(sut.fontSize, 32)
    }

    func test_setFontSize_exactMinimum_acceptedAsIs() {
        // Act
        sut.setFontSize(10)

        // Assert
        XCTAssertEqual(sut.fontSize, 10)
    }

    func test_setFontSize_exactMaximum_acceptedAsIs() {
        // Act
        sut.setFontSize(32)

        // Assert
        XCTAssertEqual(sut.fontSize, 32)
    }

    func test_setFontSize_negativeValue_clampedTo10() {
        // Act
        sut.setFontSize(-1)

        // Assert
        XCTAssertEqual(sut.fontSize, 10)
    }

    func test_setFontSize_zero_clampedTo10() {
        // Act
        sut.setFontSize(0)

        // Assert
        XCTAssertEqual(sut.fontSize, 10)
    }

    func test_increaseFontSize_incrementsByTwo() {
        // Arrange
        sut.setFontSize(16)

        // Act
        sut.increaseFontSize()

        // Assert
        XCTAssertEqual(sut.fontSize, 18)
    }

    func test_decreaseFontSize_decrementsByTwo() {
        // Arrange
        sut.setFontSize(16)

        // Act
        sut.decreaseFontSize()

        // Assert
        XCTAssertEqual(sut.fontSize, 14)
    }

    func test_resetFontSize_setsTo16() {
        // Arrange
        sut.setFontSize(28)

        // Act
        sut.resetFontSize()

        // Assert
        XCTAssertEqual(sut.fontSize, 16)
    }

    func test_increaseFontSize_atMaximum_staysAt32() {
        // Arrange
        sut.setFontSize(32)

        // Act
        sut.increaseFontSize()

        // Assert
        XCTAssertEqual(sut.fontSize, 32)
    }

    func test_decreaseFontSize_atMinimum_staysAt10() {
        // Arrange
        sut.setFontSize(10)

        // Act
        sut.decreaseFontSize()

        // Assert
        XCTAssertEqual(sut.fontSize, 10)
    }

    // MARK: - escapeForJS (tested via rendererReady + WKWebView-less path)

    func test_escapeForJS_noSpecialChars_rendererNotReadyStoresPending() {
        // Arrange — renderer not yet ready
        XCTAssertFalse(sut.isRendererReady)

        // Act — should not crash even without webView
        sut.renderMarkdown("Hello World")

        // Assert — no crash, pending state recorded internally
        // (pendingMarkdown is private; we verify by confirming no crash)
    }

    func test_rendererDidLoad_setsRendererReady() {
        // Act
        sut.rendererDidLoad()

        // Assert
        XCTAssertTrue(sut.isRendererReady)
    }

    func test_renderMarkdown_afterRendererReady_doesNotCrashWithoutWebView() {
        // Arrange
        sut.rendererDidLoad()

        // Act — webView is nil, evaluateJavaScript should not be called, no crash
        sut.renderMarkdown("# Hello")

        // Assert — no crash
    }

    // MARK: - applySystemAppearance

    func test_applySystemAppearance_lightThemeAndDarkMode_switchesToGithubDark() {
        // Arrange
        sut.setTheme(.githubLight)

        // Act
        sut.applySystemAppearance(isDark: true)

        // Assert
        XCTAssertEqual(sut.theme, .githubDark)
    }

    func test_applySystemAppearance_darkThemeAndLightMode_switchesToGithubLight() {
        // Arrange
        sut.setTheme(.githubDark)

        // Act
        sut.applySystemAppearance(isDark: false)

        // Assert
        XCTAssertEqual(sut.theme, .githubLight)
    }

    func test_applySystemAppearance_nonGithubThemeAndDarkMode_doesNotChangeTheme() {
        // Arrange
        sut.setTheme(MarkdownTheme.all.first(where: { $0.id == "dracula" })!)

        // Act
        sut.applySystemAppearance(isDark: true)

        // Assert — non-GitHub theme should not be changed
        XCTAssertEqual(sut.theme.id, "dracula")
    }

    func test_applySystemAppearance_nonGithubThemeAndLightMode_doesNotChangeTheme() {
        // Arrange
        sut.setTheme(MarkdownTheme.all.first(where: { $0.id == "nord" })!)

        // Act
        sut.applySystemAppearance(isDark: false)

        // Assert
        XCTAssertEqual(sut.theme.id, "nord")
    }

    func test_applySystemAppearance_lightThemeAndLightMode_doesNotChangeTheme() {
        // Arrange
        sut.setTheme(.githubLight)

        // Act
        sut.applySystemAppearance(isDark: false)

        // Assert
        XCTAssertEqual(sut.theme, .githubLight)
    }

    func test_applySystemAppearance_darkThemeAndDarkMode_doesNotChangeTheme() {
        // Arrange
        sut.setTheme(.githubDark)

        // Act
        sut.applySystemAppearance(isDark: true)

        // Assert
        XCTAssertEqual(sut.theme, .githubDark)
    }
}
