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

/// 最後のウィンドウを閉じたあとにすること。ウェルカム画面を出す設定は既定でオン（#13 の動き）。
final class LastWindowClosedActionTests: XCTestCase {
    func test_welcomeOn_lastDocumentClosed_showsWelcome() {
        XCTAssertEqual(
            LastWindowClosedAction.decide(isTerminating: false, closedDocument: true, showsWelcome: true),
            .showWelcome
        )
    }

    func test_welcomeOn_welcomeClosed_quits() {
        XCTAssertEqual(
            LastWindowClosedAction.decide(isTerminating: false, closedDocument: false, showsWelcome: true),
            .quit
        )
    }

    /// オフなら、ほかの Mac のアプリと同じく、ウィンドウを出さずに起動し続ける
    func test_welcomeOff_lastDocumentClosed_keepsRunning() {
        XCTAssertEqual(
            LastWindowClosedAction.decide(isTerminating: false, closedDocument: true, showsWelcome: false),
            .keepRunning
        )
    }

    /// オフのときは、起動時のウェルカム画面や空の新規文書を閉じても終了しない
    func test_welcomeOff_welcomeClosed_keepsRunning() {
        XCTAssertEqual(
            LastWindowClosedAction.decide(isTerminating: false, closedDocument: false, showsWelcome: false),
            .keepRunning
        )
    }

    /// ⌘Q の終了処理中は、設定に関係なく何も出さずに終了する
    func test_terminating_quitsRegardlessOfSetting() {
        for closedDocument in [true, false] {
            for showsWelcome in [true, false] {
                XCTAssertEqual(
                    LastWindowClosedAction.decide(
                        isTerminating: true,
                        closedDocument: closedDocument,
                        showsWelcome: showsWelcome
                    ),
                    .quit
                )
            }
        }
    }
}
