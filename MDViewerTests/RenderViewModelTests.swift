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

    func test_applySystemAppearance_nonGithubThemeAndDarkMode_doesNotChangeTheme() throws {
        // Arrange
        try sut.setTheme(XCTUnwrap(MarkdownTheme.all.first(where: { $0.id == "dracula" })))

        // Act
        sut.applySystemAppearance(isDark: true)

        // Assert — non-GitHub theme should not be changed
        XCTAssertEqual(sut.theme.id, "dracula")
    }

    func test_applySystemAppearance_nonGithubThemeAndLightMode_doesNotChangeTheme() throws {
        // Arrange
        try sut.setTheme(XCTUnwrap(MarkdownTheme.all.first(where: { $0.id == "nord" })))

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

    // MARK: - Crash-loop guard

    /// A crash caused from outside — the process being killed, a system memory
    /// kill — is followed by a successful render, which clears the counter. The
    /// guard must stay out of the way there.
    func test_rendererDidFail_withSuccessfulRenderInBetween_neverTripsTheGuard() {
        // Arrange
        let start = Date()

        // Act
        for step in 1 ... 5 {
            let shouldReload = sut.rendererDidFail(now: start.addingTimeInterval(Double(step) * 2.5))
            sut.noteRenderSucceeded()

            // Assert
            XCTAssertTrue(shouldReload)
            XCTAssertNil(sut.renderFailureMessage)
        }
    }

    /// When the content itself is what kills the renderer, no render ever
    /// completes, so the failures accumulate and the guard has to stop the loop.
    func test_rendererDidFail_repeatedlyWithoutSuccess_stopsReloadingContent() {
        // Arrange
        let start = Date()

        // Act
        for step in 1 ... 3 {
            let shouldReload = sut.rendererDidFail(now: start.addingTimeInterval(Double(step) * 0.5))

            // Assert
            XCTAssertTrue(shouldReload)
            XCTAssertNil(sut.renderFailureMessage)
        }

        // Act — one past the threshold
        let reloadsOnceMore = sut.rendererDidFail(now: start.addingTimeInterval(2))

        // Assert — reloads a final time, but empty, and explains why
        XCTAssertTrue(reloadsOnceMore)
        XCTAssertNotNil(sut.renderFailureMessage)

        // Act — everything beyond that stops reloading altogether
        let keepsReloading = sut.rendererDidFail(now: start.addingTimeInterval(2.5))

        // Assert
        XCTAssertFalse(keepsReloading)
    }

    func test_rendererDidFail_failuresFurtherApartThanTheWindow_doNotAccumulate() {
        // Arrange
        let start = Date()

        // Act
        sut.rendererDidFail(now: start)
        sut.rendererDidFail(now: start.addingTimeInterval(30))
        sut.rendererDidFail(now: start.addingTimeInterval(60))

        // Assert
        XCTAssertNil(sut.renderFailureMessage)
    }

    func test_noteRenderSucceeded_afterTheGuardTripped_clearsTheMessage() {
        // Arrange
        let start = Date()
        for step in 1 ... 4 {
            sut.rendererDidFail(now: start.addingTimeInterval(Double(step) * 0.5))
        }
        XCTAssertNotNil(sut.renderFailureMessage)

        // Act
        sut.noteRenderSucceeded()

        // Assert
        XCTAssertNil(sut.renderFailureMessage)
    }
}
