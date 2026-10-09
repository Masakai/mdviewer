import XCTest
@testable import MDViewer

/// 設定 > 一般 のスイッチ（起動時の復元・自動再読み込み）が効くことを確かめる（#18）
@MainActor
final class DocumentViewModelSettingsTests: XCTestCase {
    var defaults: UserDefaults!
    var suiteName: String!
    var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "DocumentViewModelSettingsTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DocumentViewModelSettingsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    private func makeFile(_ name: String, content: String) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func makeViewModel() -> DocumentViewModel {
        DocumentViewModel(openDocumentStore: OpenDocumentStore(defaults: defaults), settings: defaults)
    }

    private func collectOpenInWindowURLs(_ body: () -> Void) -> [URL] {
        var received: [URL] = []
        let token = NotificationCenter.default.addObserver(
            forName: .openDocumentInWindow, object: nil, queue: nil
        ) { if let url = $0.object as? URL { received.append(url) } }
        defer { NotificationCenter.default.removeObserver(token) }
        body()
        return received
    }

    // MARK: - 起動時の復元

    func test_restore_settingOff_staysOnWelcomeScreen() throws {
        let previous = OpenDocumentStore(defaults: defaults)
        try previous.add(url: makeFile("a.md", content: "# a"))
        try previous.add(url: makeFile("b.md", content: "# b"))
        defaults.set(false, forKey: DocumentViewModel.restoreOnLaunchKey)
        let sut = makeViewModel()

        let opened = collectOpenInWindowURLs { sut.restoreLastOpened() }

        XCTAssertFalse(sut.hasDocument)
        XCTAssertEqual(opened, [])
    }

    func test_restore_settingOff_keepsRecordsForWhenItIsTurnedBackOn() throws {
        let sut = makeViewModel()
        defaults.set(false, forKey: DocumentViewModel.restoreOnLaunchKey)
        try sut.load(url: makeFile("a.md", content: "# a"))

        // 次回起動時に設定をオンに戻した
        defaults.set(true, forKey: DocumentViewModel.restoreOnLaunchKey)
        let next = makeViewModel()
        next.restoreLastOpened()

        XCTAssertEqual(next.fileURL?.lastPathComponent, "a.md")
    }

    func test_restore_settingNotSet_restores() throws {
        try OpenDocumentStore(defaults: defaults).add(url: makeFile("a.md", content: "# a"))
        let sut = makeViewModel()

        sut.restoreLastOpened()

        XCTAssertEqual(sut.fileURL?.lastPathComponent, "a.md")
    }

    // MARK: - 自動再読み込み

    func test_fileDidChange_autoReloadOff_keepsDisplayedText() throws {
        let url = try makeFile("a.md", content: "old")
        let sut = makeViewModel()
        sut.load(url: url)
        defaults.set(false, forKey: DocumentViewModel.autoReloadKey)
        try "new".write(to: url, atomically: true, encoding: .utf8)

        sut.fileDidChange()

        XCTAssertEqual(sut.text, "old")
    }

    func test_fileDidChange_autoReloadNotSet_reloads() throws {
        let url = try makeFile("a.md", content: "old")
        let sut = makeViewModel()
        sut.load(url: url)
        try "new".write(to: url, atomically: true, encoding: .utf8)

        sut.fileDidChange()

        XCTAssertEqual(sut.text, "new")
    }

    func test_reload_autoReloadOff_stillReadsFile() throws {
        let url = try makeFile("a.md", content: "old")
        let sut = makeViewModel()
        sut.load(url: url)
        defaults.set(false, forKey: DocumentViewModel.autoReloadKey)
        try "new".write(to: url, atomically: true, encoding: .utf8)

        // ⌘R の手動再読み込みは設定に関係なく効く
        sut.reload()

        XCTAssertEqual(sut.text, "new")
    }
}
