import AppKit
import XCTest
@testable import MDViewer

/// メニューの保存を無効にするための、キーウィンドウの文書の状態（#37）。
/// テストホストのウィンドウはキーにならないので、キーの出入りはウィンドウを使わず update の引数で再現する。
@MainActor
final class KeyDocumentStateTests: XCTestCase {
    func test_initial_isNotReadOnly() {
        XCTAssertFalse(KeyDocumentState().isReadOnly)
    }

    func test_keyWindowReadOnly_isReadOnly() {
        let sut = KeyDocumentState()

        sut.update(owner: NSObject(), isKey: true, isReadOnly: true)

        XCTAssertTrue(sut.isReadOnly)
    }

    func test_keyWindowWritable_isNotReadOnly() {
        let sut = KeyDocumentState()

        sut.update(owner: NSObject(), isKey: true, isReadOnly: false)

        XCTAssertFalse(sut.isReadOnly)
    }

    func test_nonKeyWindowReadOnly_isIgnored() {
        let sut = KeyDocumentState()
        let key = NSObject()
        sut.update(owner: key, isKey: true, isReadOnly: false)

        sut.update(owner: NSObject(), isKey: false, isReadOnly: true)

        XCTAssertFalse(sut.isReadOnly)
    }

    // MARK: - キーウィンドウの切り替え

    func test_switchToWritableWindow_becomesNotReadOnly() {
        let sut = KeyDocumentState()
        let readOnly = NSObject()
        let writable = NSObject()
        sut.update(owner: readOnly, isKey: true, isReadOnly: true)

        sut.update(owner: readOnly, isKey: false, isReadOnly: true)
        sut.update(owner: writable, isKey: true, isReadOnly: false)

        XCTAssertFalse(sut.isReadOnly)
    }

    func test_switchToReadOnlyWindow_becomesReadOnly() {
        let sut = KeyDocumentState()
        let writable = NSObject()
        let readOnly = NSObject()
        sut.update(owner: writable, isKey: true, isReadOnly: false)

        sut.update(owner: writable, isKey: false, isReadOnly: false)
        sut.update(owner: readOnly, isKey: true, isReadOnly: true)

        XCTAssertTrue(sut.isReadOnly)
    }

    /// 新しいウィンドウのキーの知らせが、前のウィンドウの外れた知らせより先に届いても上書きされない
    func test_resignAfterOtherBecameKey_keepsNewValue() {
        let sut = KeyDocumentState()
        let old = NSObject()
        let new = NSObject()
        sut.update(owner: old, isKey: true, isReadOnly: false)

        sut.update(owner: new, isKey: true, isReadOnly: true)
        sut.update(owner: old, isKey: false, isReadOnly: false)

        XCTAssertTrue(sut.isReadOnly)
    }

    /// 読み取り専用の文書からヘルプや設定のウィンドウに移ったら、保存を無効のまま残さない
    func test_resignKeyWithoutOtherDocument_becomesNotReadOnly() {
        let sut = KeyDocumentState()
        let readOnly = NSObject()
        sut.update(owner: readOnly, isKey: true, isReadOnly: true)

        sut.update(owner: readOnly, isKey: false, isReadOnly: true)

        XCTAssertFalse(sut.isReadOnly)
    }

    // MARK: - 読み取り専用の変化

    func test_keyWindowBecomesReadOnly_updates() {
        let sut = KeyDocumentState()
        let owner = NSObject()
        sut.update(owner: owner, isKey: true, isReadOnly: false)

        sut.update(owner: owner, isKey: true, isReadOnly: true)
        XCTAssertTrue(sut.isReadOnly)

        sut.update(owner: owner, isKey: true, isReadOnly: false)
        XCTAssertFalse(sut.isReadOnly)
    }

    func test_backgroundWindowBecomesReadOnly_isIgnored() {
        let sut = KeyDocumentState()
        let key = NSObject()
        let background = NSObject()
        sut.update(owner: background, isKey: true, isReadOnly: false)
        sut.update(owner: background, isKey: false, isReadOnly: false)
        sut.update(owner: key, isKey: true, isReadOnly: false)

        sut.update(owner: background, isKey: false, isReadOnly: true)

        XCTAssertFalse(sut.isReadOnly)
    }

    /// ウィンドウの更新のたびに同じ値で呼ばれても、メニューを作り直させない
    func test_sameValue_doesNotPublish() {
        let sut = KeyDocumentState()
        let owner = NSObject()
        sut.update(owner: owner, isKey: true, isReadOnly: true)
        var published = 0
        let cancellable = sut.objectWillChange.sink { published += 1 }
        defer { cancellable.cancel() }

        sut.update(owner: owner, isKey: true, isReadOnly: true)
        sut.update(owner: NSObject(), isKey: false, isReadOnly: false)

        XCTAssertEqual(published, 0)
    }

    // MARK: - 閉じたとき

    func test_closeKeyWindow_becomesNotReadOnly() {
        let sut = KeyDocumentState()
        let owner = NSObject()
        sut.update(owner: owner, isKey: true, isReadOnly: true)

        sut.windowClosed(owner: owner)

        XCTAssertFalse(sut.isReadOnly)
    }

    func test_closeBackgroundWindow_keepsKeyWindowValue() {
        let sut = KeyDocumentState()
        let key = NSObject()
        sut.update(owner: key, isKey: true, isReadOnly: true)

        sut.windowClosed(owner: NSObject())

        XCTAssertTrue(sut.isReadOnly)
    }

    /// ウィンドウを閉じたときの処理（WindowCloseInterceptor）から共有の状態が戻ること。
    /// ファイルを読み込んでいないので、閉じても OpenDocumentStore には触れない。
    func test_windowCloseInterceptor_windowWillClose_resetsSharedState() throws {
        let suiteName = "com.mdviewer.app.tests.KeyDocumentState"
        UserDefaults().removePersistentDomain(forName: suiteName)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let documentVM = DocumentViewModel(openDocumentStore: OpenDocumentStore(defaults: defaults), settings: defaults)
        let coordinator = WindowCloseInterceptor.Coordinator(documentVM: documentVM)
        let window = NSWindow()
        window.isReleasedWhenClosed = false
        KeyDocumentState.shared.update(owner: documentVM, isKey: true, isReadOnly: true)
        XCTAssertTrue(KeyDocumentState.shared.isReadOnly)

        coordinator.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: window))

        XCTAssertFalse(KeyDocumentState.shared.isReadOnly)
    }

    // MARK: - メニューバーの「保存」

    /// MDViewerApp のメニューの「保存」（⌘S）が共有の状態に合わせて無効・有効になること。
    /// SwiftUI はメニューを開くときに項目を作り直すので、開くときと同じ順に NSMenuDelegate を呼んでから読む。
    func test_mainMenuSaveItem_followsSharedState() async throws {
        let owner = NSObject()
        defer { KeyDocumentState.shared.windowClosed(owner: owner) }
        XCTAssertEqual(try saveMenuItemIsEnabled(), true)

        KeyDocumentState.shared.update(owner: owner, isKey: true, isReadOnly: true)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(try saveMenuItemIsEnabled(), false)

        KeyDocumentState.shared.update(owner: owner, isKey: false, isReadOnly: true)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(try saveMenuItemIsEnabled(), true)
    }

    private func saveMenuItemIsEnabled() throws -> Bool {
        let menu = try XCTUnwrap(saveMenuItem()?.menu, "メニューに ⌘S の項目がない")
        menu.delegate?.menuNeedsUpdate?(menu)
        menu.delegate?.menuWillOpen?(menu)
        menu.update()
        menu.delegate?.menuDidClose?(menu)
        // 作り直しで項目が差し替わることがあるので、探し直してから読む
        return try XCTUnwrap(saveMenuItem()).isEnabled
    }

    private func saveMenuItem() -> NSMenuItem? {
        for top in NSApp.mainMenu?.items ?? [] {
            for item in top.submenu?.items ?? []
                where item.keyEquivalent == "s" && item.keyEquivalentModifierMask == [.command] {
                return item
            }
        }
        return nil
    }
}
