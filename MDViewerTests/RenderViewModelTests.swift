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
            XCTAssertFalse(sut.isPreviewInterrupted)
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

        XCTAssertTrue(sut.isPreviewInterrupted)

        // Act
        sut.noteRenderSucceeded()

        // Assert
        XCTAssertNil(sut.renderFailureMessage)
        XCTAssertFalse(sut.isPreviewInterrupted)
    }

    /// The reset the guard announces must be real: the reload that follows it
    /// may not draw the content that kept crashing, or the loop starts again.
    func test_rendererDidFail_guardTripped_leavesNothingToRestore() {
        // Arrange — a ready renderer showing content, as in normal use
        let start = Date()
        sut.rendererDidLoad()
        sut.renderMarkdown("# content that crashes the renderer")

        // Act
        for step in 1 ... 4 {
            sut.rendererDidFail(now: start.addingTimeInterval(Double(step) * 0.5))
        }

        // Assert
        XCTAssertNotNil(sut.renderFailureMessage)
        XCTAssertNil(sut.markdownToRestore)
    }

    /// Below the threshold a crash is recovered from, content included.
    func test_rendererDidFail_belowTheThreshold_restoresTheContent() {
        // Arrange
        sut.rendererDidLoad()
        sut.renderMarkdown("# hello")

        // Act
        sut.rendererDidFail(now: Date())

        // Assert
        XCTAssertEqual(sut.markdownToRestore, "# hello")
    }

    /// After a reset the preview comes back as soon as there is new content.
    func test_renderMarkdown_afterTheGuardTripped_restoresTheNewContent() {
        // Arrange
        let start = Date()
        sut.rendererDidLoad()
        sut.renderMarkdown("# content that crashes the renderer")
        for step in 1 ... 4 {
            sut.rendererDidFail(now: start.addingTimeInterval(Double(step) * 0.5))
        }

        // Act
        sut.renderMarkdown("# fixed content")

        // Assert
        XCTAssertEqual(sut.markdownToRestore, "# fixed content")
    }

    // MARK: - Recovery after the guard gives up

    /// Drives the guard past its last reload: four failures reset the preview,
    /// the fifth inside the window stops reloading altogether.
    private func haltRecovery(from start: Date) {
        for step in 1 ... 5 {
            sut.rendererDidFail(now: start.addingTimeInterval(Double(step) * 0.5))
        }
    }

    /// Once the guard has stopped, new content is the user trying again. It
    /// reloads the renderer once, however many edits follow before the reload
    /// finishes, and the latest one is what gets drawn.
    func test_renderMarkdown_afterRecoveryHalted_reloadsTheRendererOnce() {
        // Arrange
        haltRecovery(from: Date())
        var reloads = 0
        sut.reloadRenderer = { reloads += 1; return true }

        // Act
        sut.renderMarkdown("# a")
        sut.renderMarkdown("# ab")
        sut.renderMarkdown("# abc")

        // Assert
        XCTAssertEqual(reloads, 1)
        XCTAssertFalse(sut.isRecoveryHalted)
        XCTAssertEqual(sut.markdownToRestore, "# abc")
        XCTAssertNotNil(sut.renderFailureMessage)
    }

    /// A renderer that is loading — the first load, or a recovery in flight —
    /// is not stuck, and after the fourth failure the guard still reloads
    /// once. Neither may trigger a second load.
    func test_renderMarkdown_whileNotHalted_neverReloadsTheRenderer() {
        // Arrange
        let start = Date()
        var reloads = 0
        sut.reloadRenderer = { reloads += 1; return true }

        // Act — before the first load finishes
        sut.renderMarkdown("# first")
        // Act — after the guard reset the preview, without giving up
        for step in 1 ... 4 {
            sut.rendererDidFail(now: start.addingTimeInterval(Double(step) * 0.5))
        }
        sut.renderMarkdown("# second")

        // Assert
        XCTAssertEqual(reloads, 0)
        XCTAssertFalse(sut.isRecoveryHalted)
    }

    /// A retry gets the same budget as any other content: if it keeps
    /// crashing the guard stops it again, and the next edit may retry again.
    func test_rendererDidFail_afterARetry_haltsAgainAfterTheSameBudget() {
        // Arrange
        let start = Date()
        haltRecovery(from: start)
        var reloads = 0
        sut.reloadRenderer = { reloads += 1; return true }
        sut.renderMarkdown("# still crashing")
        sut.rendererDidLoad()  // the retried page loads, then the content crashes it
        let retry = start.addingTimeInterval(3)

        // Act
        var results: [Bool] = []
        for step in 1 ... 5 {
            results.append(sut.rendererDidFail(now: retry.addingTimeInterval(Double(step) * 0.5)))
        }

        // Assert
        XCTAssertEqual(results, [true, true, true, true, false])
        XCTAssertTrue(sut.isRecoveryHalted)
        XCTAssertNil(sut.markdownToRestore)

        // Act — the user tries again
        sut.renderMarkdown("# fixed")

        // Assert
        XCTAssertEqual(reloads, 2)
        XCTAssertEqual(sut.markdownToRestore, "# fixed")
    }

    /// Any page that finishes loading means the renderer is back, with a
    /// fresh budget: a crash right after must be reloaded, not counted as the
    /// sixth failure of the budget that was already used up.
    func test_rendererDidLoad_afterRecoveryHalted_clearsTheHaltWithAFreshBudget() {
        // Arrange
        let start = Date()
        haltRecovery(from: start)
        XCTAssertTrue(sut.isRecoveryHalted)
        var reloads = 0
        sut.reloadRenderer = { reloads += 1; return true }

        // Act
        sut.rendererDidLoad()
        sut.renderMarkdown("# drawn directly")
        let reloadsAfterCrash = sut.rendererDidFail(now: start.addingTimeInterval(3))

        // Assert
        XCTAssertEqual(reloads, 0)
        XCTAssertTrue(reloadsAfterCrash)
        XCTAssertFalse(sut.isRecoveryHalted)
    }

    /// With no renderer on screen nothing is reloaded, so the halt must stay
    /// for the next attempt to retry.
    func test_renderMarkdown_haltedWithoutARenderer_staysHalted() {
        // Arrange
        haltRecovery(from: Date())
        var available = false
        var reloads = 0
        sut.reloadRenderer = { reloads += 1; return available }

        // Act
        sut.renderMarkdown("# nowhere to draw")

        // Assert
        XCTAssertTrue(sut.isRecoveryHalted)

        // Act — the renderer is back on screen
        available = true
        sut.renderMarkdown("# drawn")

        // Assert
        XCTAssertFalse(sut.isRecoveryHalted)
        XCTAssertEqual(reloads, 2)
    }

    // MARK: - Preview interrupted

    func test_rendererDidFail_fourthFailureInTheWindow_interruptsThePreview() {
        // Arrange
        let start = Date()
        for step in 1 ... 3 {
            sut.rendererDidFail(now: start.addingTimeInterval(Double(step) * 0.5))
            XCTAssertFalse(sut.isPreviewInterrupted)
        }

        // Act
        sut.rendererDidFail(now: start.addingTimeInterval(2))

        // Assert
        XCTAssertTrue(sut.isPreviewInterrupted)
    }

    func test_rendererDidFail_belowTheThreshold_doesNotInterruptThePreview() {
        // Arrange
        let start = Date()

        // Act
        for step in 1 ... 3 {
            sut.rendererDidFail(now: start.addingTimeInterval(Double(step) * 0.5))
        }

        // Assert
        XCTAssertFalse(sut.isPreviewInterrupted)
    }

    /// The alert is shown once and dismissed; the preview is still showing the
    /// reset (or halted) renderer, so the interruption must outlive it.
    func test_isPreviewInterrupted_afterTheAlertIsDismissed_staysSet() {
        // Arrange
        let start = Date()
        for step in 1 ... 4 {
            sut.rendererDidFail(now: start.addingTimeInterval(Double(step) * 0.5))
        }

        // Act — alert OK after the reset
        sut.renderFailureMessage = nil

        // Assert
        XCTAssertTrue(sut.isPreviewInterrupted)

        // Act — halt, alert OK again, then the empty page loads
        sut.rendererDidFail(now: start.addingTimeInterval(2.5))
        sut.renderFailureMessage = nil
        sut.rendererDidLoad()

        // Assert
        XCTAssertTrue(sut.isPreviewInterrupted)
    }

    /// The page that loads after a halt zeroes the budget and the alert has
    /// been dismissed, so the interruption is the only thing left to clear:
    /// a successful render must still clear it, or the banner stays forever.
    func test_noteRenderSucceeded_afterHaltLoadAndDismissedAlert_clearsTheInterruption() {
        // Arrange
        haltRecovery(from: Date())
        sut.rendererDidLoad()
        sut.renderFailureMessage = nil
        XCTAssertTrue(sut.isPreviewInterrupted)

        // Act
        sut.noteRenderSucceeded()

        // Assert
        XCTAssertFalse(sut.isPreviewInterrupted)
    }

    /// A failure after the window restarts the count, but the preview is
    /// still the reset one: nothing has rendered since.
    func test_rendererDidFail_afterTheWindowWhileInterrupted_staysInterrupted() {
        // Arrange
        let start = Date()
        for step in 1 ... 4 {
            sut.rendererDidFail(now: start.addingTimeInterval(Double(step) * 0.5))
        }

        // Act
        sut.rendererDidFail(now: start.addingTimeInterval(30))

        // Assert
        XCTAssertTrue(sut.isPreviewInterrupted)
    }

    /// Try Again after the reset gets a fresh budget: the next failures inside
    /// the window of the fourth are recovered from instead of halting.
    func test_retryRendering_afterTheReset_givesAFreshBudgetAndRestoresTheText() {
        // Arrange
        let start = Date()
        sut.rendererDidLoad()
        sut.renderMarkdown("# content that crashes the renderer")
        for step in 1 ... 4 {
            sut.rendererDidFail(now: start.addingTimeInterval(Double(step) * 0.5))
        }
        var reloads = 0
        sut.reloadRenderer = { reloads += 1; return true }

        // Act
        sut.retryRendering("# try again")

        // Assert
        XCTAssertEqual(reloads, 0)
        XCTAssertEqual(sut.markdownToRestore, "# try again")
        XCTAssertTrue(sut.isPreviewInterrupted)

        // Act — it crashes again, inside the window of the fourth failure
        let retry = start.addingTimeInterval(3)
        var results: [Bool] = []
        for step in 1 ... 3 {
            results.append(sut.rendererDidFail(now: retry.addingTimeInterval(Double(step) * 0.5)))
        }

        // Assert
        XCTAssertEqual(results, [true, true, true])
        XCTAssertFalse(sut.isRecoveryHalted)
    }

    func test_retryRendering_whenHalted_reloadsOnceAndKeepsTheLatestText() {
        // Arrange
        haltRecovery(from: Date())
        var reloads = 0
        sut.reloadRenderer = { reloads += 1; return true }

        // Act
        sut.retryRendering("# a")
        sut.retryRendering("# ab")

        // Assert
        XCTAssertEqual(reloads, 1)
        XCTAssertFalse(sut.isRecoveryHalted)
        XCTAssertEqual(sut.markdownToRestore, "# ab")
        XCTAssertTrue(sut.isPreviewInterrupted)
    }

    func test_retryRendering_haltedWithoutARenderer_staysHaltedAndInterrupted() {
        // Arrange
        haltRecovery(from: Date())

        // Act — no reloadRenderer at all
        sut.retryRendering("# nowhere to draw")

        // Assert
        XCTAssertTrue(sut.isRecoveryHalted)
        XCTAssertTrue(sut.isPreviewInterrupted)

        // Act — a renderer that cannot reload
        sut.reloadRenderer = { false }
        sut.retryRendering("# nowhere to draw")
        sut.retryRendering("# nowhere to draw")

        // Assert
        XCTAssertTrue(sut.isRecoveryHalted)
        XCTAssertTrue(sut.isPreviewInterrupted)
    }

    /// Mid crash-loop, before any reset, Try Again is not on screen; a call
    /// anyway must not hand the crashing content a fresh budget.
    func test_retryRendering_whenNotInterrupted_leavesTheBudgetAlone() {
        // Arrange
        let start = Date()
        var reloads = 0
        sut.reloadRenderer = { reloads += 1; return true }
        for step in 1 ... 3 {
            sut.rendererDidFail(now: start.addingTimeInterval(Double(step) * 0.5))
        }

        // Act
        sut.retryRendering("# not now")
        sut.rendererDidFail(now: start.addingTimeInterval(2))

        // Assert — the fourth failure still resets the preview
        XCTAssertNotNil(sut.renderFailureMessage)
        XCTAssertTrue(sut.isPreviewInterrupted)
        XCTAssertEqual(reloads, 0)
    }

    func test_rendererDidFail_resetAndHalt_callOnPreviewResetEachTime() {
        // Arrange
        let start = Date()
        var resets = 0
        sut.onPreviewReset = { resets += 1 }

        // Act
        for step in 1 ... 3 {
            sut.rendererDidFail(now: start.addingTimeInterval(Double(step) * 0.5))
        }

        // Assert
        XCTAssertEqual(resets, 0)

        // Act — the reset
        sut.rendererDidFail(now: start.addingTimeInterval(2))

        // Assert
        XCTAssertEqual(resets, 1)

        // Act — the halt
        sut.rendererDidFail(now: start.addingTimeInterval(2.5))

        // Assert
        XCTAssertEqual(resets, 2)
    }

    /// The user scenario end to end: halted, alert dismissed, Try Again
    /// reloads the renderer and the retried content renders.
    func test_retryRendering_haltedThenRenderSucceeds_clearsTheInterruption() {
        // Arrange
        haltRecovery(from: Date())
        sut.renderFailureMessage = nil
        sut.reloadRenderer = { true }

        // Act
        sut.retryRendering("# fixed")
        sut.rendererDidLoad()
        sut.noteRenderSucceeded()

        // Assert
        XCTAssertFalse(sut.isPreviewInterrupted)
        XCTAssertNil(sut.renderFailureMessage)
    }
}
