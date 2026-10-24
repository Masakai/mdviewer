import XCTest
@testable import MDViewer

final class DocumentCloseTrackerTests: XCTestCase {
    func test_lastDocumentClosed_showsWelcome() {
        var sut = DocumentCloseTracker()
        sut.windowWillClose(hadDocument: true)

        XCTAssertTrue(sut.consumeForLastWindowClosed())
    }

    func test_welcomeClosed_quits() {
        var sut = DocumentCloseTracker()
        sut.windowWillClose(hadDocument: false)

        XCTAssertFalse(sut.consumeForLastWindowClosed())
    }

    func test_mixedTabGroup_documentFirstThenWelcome_showsWelcome() {
        var sut = DocumentCloseTracker()
        sut.windowWillClose(hadDocument: true)
        sut.windowWillClose(hadDocument: false)

        XCTAssertTrue(sut.consumeForLastWindowClosed())
    }

    func test_mixedTabGroup_welcomeFirstThenDocument_showsWelcome() {
        var sut = DocumentCloseTracker()
        sut.windowWillClose(hadDocument: false)
        sut.windowWillClose(hadDocument: true)

        XCTAssertTrue(sut.consumeForLastWindowClosed())
    }

    func test_documentClosedWhileOtherWindowsRemain_thenWelcomeClosedLater_quits() {
        var sut = DocumentCloseTracker()
        sut.windowWillClose(hadDocument: true)
        sut.closingFinished(windowsRemain: true)
        sut.windowWillClose(hadDocument: false)

        XCTAssertFalse(sut.consumeForLastWindowClosed())
    }

    func test_closingFinishedWithoutRemainingWindows_keepsRecordForLastWindowDecision() {
        var sut = DocumentCloseTracker()
        sut.windowWillClose(hadDocument: true)
        sut.closingFinished(windowsRemain: false)

        XCTAssertTrue(sut.consumeForLastWindowClosed())
    }

    func test_consume_resetsRecord() {
        var sut = DocumentCloseTracker()
        sut.windowWillClose(hadDocument: true)
        _ = sut.consumeForLastWindowClosed()

        XCTAssertFalse(sut.consumeForLastWindowClosed())
    }
}
