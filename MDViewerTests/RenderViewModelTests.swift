import Combine
import WebKit
import XCTest
@testable import MDViewer

/// A WKWebView that only records the scripts passed to evaluateJavaScript.
private final class ScriptRecordingWebView: WKWebView {
    var scripts: [String] = []

    override func evaluateJavaScript(_ javaScriptString: String, completionHandler: (@MainActor @Sendable (Any?, Error?) -> Void)? = nil) {
        scripts.append(javaScriptString)
    }
}

@MainActor
final class RenderViewModelTests: XCTestCase {
    var sut: RenderViewModel!
    /// テストホストは本番と同じバンドルIDなので、.standard に書くと利用者の文字サイズやテーマが変わる
    var defaults: UserDefaults!
    /// 名前を固定する。テストごとに名前を変えると、removePersistentDomain の後も空の plist が
    /// ~/Library/Preferences に1個ずつ残る。scheme は並列実行しないので固定名でも衝突しない
    let suiteName = "com.mdviewer.app.tests.RenderViewModel"

    override func setUp() async throws {
        try await super.setUp()
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        // 前回の実行が途中で止まって残った値を消す
        defaults.removePersistentDomain(forName: suiteName)
        sut = RenderViewModel(settings: defaults, systemIsDark: false, systemAppearanceChanges: Empty<Bool, Never>().eraseToAnyPublisher())
    }

    override func tearDown() async throws {
        sut = nil
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
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

    // MARK: - Following the system appearance

    private func makeVM(
        systemIsDark: Bool,
        changes: AnyPublisher<Bool, Never> = Empty<Bool, Never>().eraseToAnyPublisher()
    ) -> RenderViewModel {
        RenderViewModel(settings: defaults, systemIsDark: systemIsDark, systemAppearanceChanges: changes)
    }

    // MARK: - Theme of the first paint

    func test_initialThemeScriptSource_nord() throws {
        let nord = try XCTUnwrap(MarkdownTheme.withId("nord"))
        XCTAssertEqual(
            RenderViewModel.initialThemeScriptSource(for: nord),
            "window.MDViewerInitialTheme = { css: 'nord', isDark: true, background: '#2e3440' };"
        )
    }

    func test_setTheme_replacesInitialThemeUserScript() throws {
        let wv = WKWebView()
        sut.webView = wv

        sut.setTheme(try XCTUnwrap(MarkdownTheme.withId("nord")))
        sut.setTheme(try XCTUnwrap(MarkdownTheme.withId("dracula")))

        let scripts = wv.configuration.userContentController.userScripts
        XCTAssertEqual(scripts.count, 1)
        XCTAssertTrue(scripts[0].source.contains("'dracula'"))
        XCTAssertEqual(scripts[0].injectionTime, .atDocumentStart)
    }

    func test_installInitialThemeScript_withoutWebView_doesNothing() {
        sut.installInitialThemeScript()
    }

    func test_needsRerenderForThemeChange() {
        XCTAssertTrue(RenderViewModel.needsRerenderForThemeChange(
            from: .githubLight, to: .githubDark, hasDiagrams: true, isRenderInFlight: false))
        XCTAssertTrue(RenderViewModel.needsRerenderForThemeChange(
            from: .githubDark, to: .githubLight, hasDiagrams: false, isRenderInFlight: true))
        XCTAssertFalse(RenderViewModel.needsRerenderForThemeChange(
            from: .githubLight, to: .githubLight, hasDiagrams: true, isRenderInFlight: true))
        XCTAssertFalse(RenderViewModel.needsRerenderForThemeChange(
            from: .githubDark, to: .githubLight, hasDiagrams: false, isRenderInFlight: false))
    }

    func test_systemAppearanceFlip_withDiagramOnScreen_rendersAgainAfterTheme() throws {
        let recorder = ScriptRecordingWebView(frame: .zero, configuration: WKWebViewConfiguration())
        sut.webView = recorder
        sut.rendererDidLoad()
        sut.renderMarkdown("```mermaid\ngraph TD; A-->B\n```")
        sut.noteRenderSucceeded(hasDiagrams: true)
        recorder.scripts.removeAll()

        sut.applySystemAppearance(isDark: true)

        let themeIndex = try XCTUnwrap(recorder.scripts.firstIndex { $0.contains("MDViewer.setTheme(") })
        let renderIndex = try XCTUnwrap(recorder.scripts.lastIndex { $0.contains("MDViewer.setContent(") })
        XCTAssertGreaterThan(renderIndex, themeIndex)
    }

    func test_systemAppearanceFlip_withoutDiagram_doesNotRenderAgain() {
        let recorder = ScriptRecordingWebView(frame: .zero, configuration: WKWebViewConfiguration())
        sut.webView = recorder
        sut.rendererDidLoad()
        sut.renderMarkdown("# Title")
        sut.noteRenderSucceeded(hasDiagrams: false)
        recorder.scripts.removeAll()

        sut.applySystemAppearance(isDark: true)

        XCTAssertTrue(recorder.scripts.contains { $0.contains("MDViewer.setTheme(") })
        XCTAssertFalse(recorder.scripts.contains { $0.contains("MDViewer.setContent(") })
    }

    func test_systemAppearanceFlip_wordMermaidWithoutDiagram_doesNotRenderAgain() {
        let recorder = ScriptRecordingWebView(frame: .zero, configuration: WKWebViewConfiguration())
        sut.webView = recorder
        sut.rendererDidLoad()
        sut.renderMarkdown("Notes about `mermaid` and Mermaid syntax.")
        sut.noteRenderSucceeded(hasDiagrams: false)
        recorder.scripts.removeAll()

        sut.applySystemAppearance(isDark: true)

        XCTAssertFalse(recorder.scripts.contains { $0.contains("MDViewer.setContent(") })
    }

    func test_systemAppearanceFlip_whileRenderInFlight_rendersAgain() {
        let recorder = ScriptRecordingWebView(frame: .zero, configuration: WKWebViewConfiguration())
        sut.webView = recorder
        sut.rendererDidLoad()
        sut.renderMarkdown("# Title")
        sut.noteRenderSucceeded(hasDiagrams: false)
        sut.renderMarkdown("```mermaid\ngraph TD; A-->B\n```")
        recorder.scripts.removeAll()

        sut.applySystemAppearance(isDark: true)

        XCTAssertTrue(recorder.scripts.contains { $0.contains("MDViewer.setContent(") })
    }

    func test_setTheme_sameAsResolvedTheme_stillPins() {
        let vm = makeVM(systemIsDark: true)
        XCTAssertEqual(vm.theme, .githubDark)

        vm.setTheme(.githubDark)
        vm.applySystemAppearance(isDark: false)

        XCTAssertEqual(vm.theme, .githubDark)
        XCTAssertEqual(vm.windowThemeOverride, .githubDark)
    }

    func test_init_followOn_darkSystem_usesDarkSlot() {
        defaults.set("nord", forKey: "darkThemeId")

        let vm = makeVM(systemIsDark: true)

        XCTAssertEqual(vm.theme.id, "nord")
    }

    func test_init_followOff_ignoresSystem() {
        defaults.set(false, forKey: "followSystemAppearance")
        defaults.set("solarized-light", forKey: "selectedThemeId")

        let vm = makeVM(systemIsDark: true)

        XCTAssertEqual(vm.theme.id, "solarized-light")
    }

    func test_applySystemAppearance_followOn_switchesSlot() {
        defaults.set(true, forKey: "followSystemAppearance")
        defaults.set("solarized-light", forKey: "lightThemeId")
        defaults.set("dracula", forKey: "darkThemeId")
        let vm = makeVM(systemIsDark: false)
        XCTAssertEqual(vm.theme.id, "solarized-light")

        vm.applySystemAppearance(isDark: true)
        XCTAssertEqual(vm.theme.id, "dracula")

        vm.applySystemAppearance(isDark: false)
        XCTAssertEqual(vm.theme.id, "solarized-light")
    }

    func test_applySystemAppearance_followOff_keepsFixedTheme() {
        defaults.set(false, forKey: "followSystemAppearance")
        defaults.set("solarized-light", forKey: "selectedThemeId")
        let vm = makeVM(systemIsDark: false)

        vm.applySystemAppearance(isDark: true)

        XCTAssertEqual(vm.theme.id, "solarized-light")
    }

    func test_systemAppearancePublisher_appliesChange() {
        let subject = PassthroughSubject<Bool, Never>()
        let vm = makeVM(systemIsDark: false, changes: subject.eraseToAnyPublisher())

        subject.send(true)

        let applied = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in vm.theme.isDark },
            object: nil
        )
        wait(for: [applied], timeout: 2)
    }

    func test_setTheme_pinsWindow_ignoresAppearanceChange() {
        let vm = makeVM(systemIsDark: false)

        vm.setTheme(.githubLight)
        vm.applySystemAppearance(isDark: true)

        XCTAssertEqual(vm.theme, .githubLight)
    }

    func test_setTheme_pinsWindow_ignoresPreviewThemeChanged() {
        let vm = makeVM(systemIsDark: false)
        vm.setTheme(.githubLight)

        defaults.set("solarized-light", forKey: "lightThemeId")
        NotificationCenter.default.post(name: .previewThemeChanged, object: nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        XCTAssertEqual(vm.theme, .githubLight)
    }

    func test_useSettingsTheme_afterAppearanceChangedWhilePinned_usesCurrentAppearance() throws {
        defaults.set(true, forKey: "followSystemAppearance")
        defaults.set("dracula", forKey: "darkThemeId")
        let vm = makeVM(systemIsDark: false)

        try vm.setTheme(XCTUnwrap(MarkdownTheme.withId("solarized-light")))
        vm.applySystemAppearance(isDark: true)
        XCTAssertEqual(vm.theme.id, "solarized-light")

        vm.useSettingsTheme()

        XCTAssertEqual(vm.theme.id, "dracula")
        XCTAssertNil(vm.windowThemeOverride)
    }

    func test_previewThemeChanged_followTurnedOn_appliesSlotForCurrentAppearance() {
        defaults.set(false, forKey: "followSystemAppearance")
        defaults.set("github-light", forKey: "selectedThemeId")
        let vm = makeVM(systemIsDark: true)
        XCTAssertEqual(vm.theme, .githubLight)

        defaults.set(true, forKey: "followSystemAppearance")
        defaults.set("dracula", forKey: "darkThemeId")
        NotificationCenter.default.post(name: .previewThemeChanged, object: nil)

        let applied = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in vm.theme.id == "dracula" },
            object: nil
        )
        wait(for: [applied], timeout: 2)
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

    // MARK: - setThemeScript

    /// Nord や Dracula は名前に dark を含まないので、ダークかどうかを明示的に渡す（#14）
    func test_setThemeScript_darkThemeWithoutDarkInName_passesTrue() throws {
        let nord = try XCTUnwrap(MarkdownTheme.all.first(where: { $0.id == "nord" }))
        XCTAssertEqual(RenderViewModel.setThemeScript(for: nord), "MDViewer.setTheme('nord', true)")
    }

    func test_setThemeScript_lightTheme_passesFalse() throws {
        let solarizedLight = try XCTUnwrap(MarkdownTheme.all.first(where: { $0.id == "solarized-light" }))
        XCTAssertEqual(
            RenderViewModel.setThemeScript(for: solarizedLight),
            "MDViewer.setTheme('solarized-light', false)"
        )
    }

    // MARK: - 数式の区切り（#31）

    /// 保存された値がなければオフ。\[ を括弧のエスケープとして書いた文書の表示を変えないため
    func test_mathBracketDelimiters_noSavedSetting_isOff() {
        XCTAssertFalse(sut.mathBracketDelimiters)
    }

    func test_mathBracketDelimiters_savedOn_isOn() {
        // Arrange
        defaults.set(true, forKey: RenderViewModel.mathBracketDelimitersKey)

        // Act & Assert
        XCTAssertTrue(sut.mathBracketDelimiters)
    }

    func test_setMathOptionsScript_passesFlag() {
        XCTAssertEqual(
            RenderViewModel.setMathOptionsScript(bracketDelimiters: true),
            "MDViewer.setMathOptions({ bracketDelimiters: true })"
        )
        XCTAssertEqual(
            RenderViewModel.setMathOptionsScript(bracketDelimiters: false),
            "MDViewer.setMathOptions({ bracketDelimiters: false })"
        )
    }

    // MARK: - 設定画面のテーマ変更（#19）

    // MARK: - 設定画面の文字サイズ変更

    func test_previewFontSizeChanged_appliesFontSizeWithoutWritingSettings() {
        let standardBefore = UserDefaults.standard.object(forKey: "fontSize") as? NSObject

        NotificationCenter.default.post(name: .previewFontSizeChanged, object: 21.0)

        let applied = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in self.sut.fontSize == 21 },
            object: nil
        )
        wait(for: [applied], timeout: 2)
        XCTAssertNil(defaults.object(forKey: "fontSize"))
        XCTAssertEqual(UserDefaults.standard.object(forKey: "fontSize") as? NSObject, standardBefore)
    }

    func test_previewFontSizeChanged_aboveMaximum_clampedTo32() {
        NotificationCenter.default.post(name: .previewFontSizeChanged, object: 100.0)

        let applied = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in self.sut.fontSize == 32 },
            object: nil
        )
        wait(for: [applied], timeout: 2)
    }

    func test_previewFontSizeChanged_belowMinimum_clampedTo10() {
        NotificationCenter.default.post(name: .previewFontSizeChanged, object: 5.0)

        let applied = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in self.sut.fontSize == 10 },
            object: nil
        )
        wait(for: [applied], timeout: 2)
    }

    func test_previewFontSizeChanged_nonNumberObject_keepsCurrentSize() {
        sut.setFontSize(18)

        NotificationCenter.default.post(name: .previewFontSizeChanged, object: "20")
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        XCTAssertEqual(sut.fontSize, 18)
    }

    // MARK: - ツールバーでのテーマ変更は設定に書かない（#14）

    func test_setTheme_doesNotWriteSelectedThemeIdToSettings() throws {
        let key = "selectedThemeId"
        defaults.set("github-light", forKey: key)

        try sut.setTheme(XCTUnwrap(MarkdownTheme.all.first(where: { $0.id == "nord" })))

        XCTAssertEqual(sut.theme.id, "nord")
        XCTAssertEqual(defaults.string(forKey: key), "github-light")
    }

    // MARK: - 設定の保存先

    func test_init_readsThemeAndFontSizeFromGivenSettings() {
        defaults.set("nord", forKey: "selectedThemeId")
        defaults.set(20.0, forKey: "fontSize")

        let vm = RenderViewModel(settings: defaults, systemIsDark: true, systemAppearanceChanges: Empty<Bool, Never>().eraseToAnyPublisher())

        XCTAssertEqual(vm.theme.id, "nord")
        XCTAssertEqual(vm.fontSize, 20)
    }

    func test_init_withoutSavedValues_usesDefaults() {
        XCTAssertEqual(sut.theme, .githubLight)
        XCTAssertEqual(sut.fontSize, 16)
        XCTAssertEqual(sut.pdfPageSize, .a4)
    }

    /// 起動引数（-fontSize 20）で渡すと文字列として入る
    func test_init_fontSizeStoredAsString_isRead() {
        defaults.set("20", forKey: "fontSize")

        let vm = RenderViewModel(settings: defaults, systemIsDark: false, systemAppearanceChanges: Empty<Bool, Never>().eraseToAnyPublisher())

        XCTAssertEqual(vm.fontSize, 20)
    }

    /// 数値として読めない値は double(forKey:) が 0 を返す。0pt では文字が見えなくなる
    func test_init_unreadableFontSize_usesDefault() {
        defaults.set("abc", forKey: "fontSize")

        let vm = RenderViewModel(settings: defaults, systemIsDark: false, systemAppearanceChanges: Empty<Bool, Never>().eraseToAnyPublisher())

        XCTAssertEqual(vm.fontSize, 16)
    }

    func test_init_zeroFontSize_usesDefault() {
        defaults.set(0.0, forKey: "fontSize")

        let vm = RenderViewModel(settings: defaults, systemIsDark: false, systemAppearanceChanges: Empty<Bool, Never>().eraseToAnyPublisher())

        XCTAssertEqual(vm.fontSize, 16)
    }

    func test_init_fontSizeOutOfRange_clamped() {
        defaults.set(100.0, forKey: "fontSize")
        XCTAssertEqual(RenderViewModel(settings: defaults, systemIsDark: false, systemAppearanceChanges: Empty<Bool, Never>().eraseToAnyPublisher()).fontSize, 32)

        defaults.set(4.0, forKey: "fontSize")
        XCTAssertEqual(RenderViewModel(settings: defaults, systemIsDark: false, systemAppearanceChanges: Empty<Bool, Never>().eraseToAnyPublisher()).fontSize, 10)
    }

    /// ツールバーや ⌘+ の変更はそのウィンドウだけに効く。同じ保存先を使う他のウィンドウには広がらない
    func test_setFontSize_doesNotChangeOtherWindowSharingSettings() {
        let other = RenderViewModel(settings: defaults, systemIsDark: false, systemAppearanceChanges: Empty<Bool, Never>().eraseToAnyPublisher())

        sut.setFontSize(20)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        XCTAssertEqual(sut.fontSize, 20)
        XCTAssertEqual(other.fontSize, 16)

        // 同じ待ち方でスライダーの通知なら届くことを確かめ、通知が届かないせいで通る偽陰性を防ぐ
        NotificationCenter.default.post(name: .previewFontSizeChanged, object: 24.0)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        XCTAssertEqual(other.fontSize, 24)
    }

    func test_setFontSize_writesToGivenSettingsOnly() {
        let standardBefore = UserDefaults.standard.object(forKey: "fontSize") as? NSObject

        sut.setFontSize(23)

        XCTAssertEqual(defaults.double(forKey: "fontSize"), 23)
        XCTAssertEqual(UserDefaults.standard.object(forKey: "fontSize") as? NSObject, standardBefore)
    }

    func test_setPDFPageSize_writesToGivenSettings() {
        sut.setPDFPageSize(.letter)

        XCTAssertEqual(defaults.string(forKey: "pdfPageSize"), PDFPageSize.letter.rawValue)
        XCTAssertEqual(sut.pdfPageSize, .letter)
    }

    // MARK: - 検索の件数

    /// 検索語を変えたら、JS から結果が届くまで前の件数を出さない。
    func test_search_clearsStatusUntilResultsArrive() {
        // Arrange
        sut.search("old")
        sut.searchResultsChanged(current: 2, total: 5)

        // Act
        sut.search("new")

        // Assert
        XCTAssertNil(sut.searchStatus)

        // Act
        sut.searchResultsChanged(current: 1, total: 3)

        // Assert
        XCTAssertEqual(sut.searchStatus, RenderViewModel.SearchStatus(current: 1, total: 3))
    }

    /// 検索を閉じた後に届いた結果（描画し直しの数え直しなど）で件数を出し直さない。
    func test_clearSearch_ignoresLateResults() {
        // Arrange
        sut.search("word")

        // Act
        sut.clearSearch()
        sut.searchResultsChanged(current: 1, total: 1)

        // Assert
        XCTAssertNil(sut.searchStatus)
    }

    func test_search_emptyQuery_clearsStatus() {
        // Arrange
        sut.search("word")
        sut.searchResultsChanged(current: 1, total: 4)

        // Act
        sut.search("")

        // Assert
        XCTAssertNil(sut.searchStatus)
    }

    // MARK: - 検索欄の入力を待ってから検索する

    /// 入力の途中では検索せず、止まってから最後の語で検索する。
    func test_searchAsTyped_waitsBeforeSearching() async throws {
        // Arrange
        sut.search("old")
        sut.searchResultsChanged(current: 2, total: 5)

        // Act
        sut.searchAsTyped("n", delay: .milliseconds(50))
        sut.searchAsTyped("ne", delay: .milliseconds(50))
        sut.searchAsTyped("new", delay: .milliseconds(50))

        // Assert: まだ前の語の件数のまま
        XCTAssertEqual(sut.searchStatus, RenderViewModel.SearchStatus(current: 2, total: 5))
        XCTAssertEqual(sut.pendingSearchQuery, "new")

        // Act
        try await Task.sleep(for: .milliseconds(300))

        // Assert: 検索したので結果待ち
        XCTAssertNil(sut.pendingSearchQuery)
        XCTAssertNil(sut.searchStatus)
    }

    /// 入力の直後に Return や矢印を押したら、待たずにその語で検索する。
    func test_findNext_afterTyping_searchesImmediately() {
        // Arrange
        sut.search("old")
        sut.searchResultsChanged(current: 2, total: 5)
        sut.searchAsTyped("new", delay: .seconds(10))

        // Act
        sut.findNext()

        // Assert
        XCTAssertNil(sut.pendingSearchQuery)
        XCTAssertNil(sut.searchStatus)
    }

    func test_searchAsTyped_empty_clearsImmediately() {
        // Arrange
        sut.search("word")
        sut.searchResultsChanged(current: 1, total: 4)
        sut.searchAsTyped("words", delay: .seconds(10))

        // Act
        sut.searchAsTyped("")

        // Assert
        XCTAssertNil(sut.pendingSearchQuery)
        XCTAssertNil(sut.searchStatus)
    }

    /// 検索バーを閉じたら、待っていた検索も取り消す。
    func test_clearSearch_cancelsPendingSearch() async throws {
        // Arrange
        sut.searchAsTyped("word", delay: .milliseconds(50))

        // Act
        sut.clearSearch()
        try await Task.sleep(for: .milliseconds(300))
        sut.searchResultsChanged(current: 1, total: 1)

        // Assert
        XCTAssertNil(sut.pendingSearchQuery)
        XCTAssertNil(sut.searchStatus)
    }

    /// 入力の直後にレンダラーが読み込み直されたら、待っていた新しい語で検索し直す。
    func test_rendererDidLoad_whileTyping_searchesThePendingQuery() {
        // Arrange
        sut.search("old")
        sut.searchAsTyped("new", delay: .seconds(10))

        // Act
        sut.rendererDidLoad()

        // Assert
        XCTAssertEqual(sut.searchQuery, "new")
        XCTAssertNil(sut.pendingSearchQuery)
    }
}
