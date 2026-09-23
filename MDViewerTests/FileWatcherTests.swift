import XCTest
@testable import MDViewer

final class FileWatcherTests: XCTestCase {

    var sut: FileWatcher!
    var tempDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()
        sut = FileWatcher()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        sut.stop()
        sut = nil
        try? FileManager.default.removeItem(at: tempDirectory)
        tempDirectory = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    /// Writes in place, keeping the same inode — TextEdit, `echo >>`, vim with
    /// `backupcopy=yes`.
    private func saveInPlace(_ file: URL, _ content: String) throws {
        let descriptor = open(file.path, O_WRONLY | O_TRUNC)
        guard descriptor != -1 else { throw CocoaError(.fileWriteUnknown) }
        defer { close(descriptor) }
        _ = content.withCString { write(descriptor, $0, strlen($0)) }
    }

    /// Writes a temporary file and renames it over the original, replacing the
    /// inode — VS Code, NSDocument, and the app's own `save()`.
    private func saveAtomically(_ file: URL, _ content: String) throws {
        let temporary = file.deletingLastPathComponent()
            .appendingPathComponent(".tmp-\(UUID().uuidString)")
        try content.write(to: temporary, atomically: false, encoding: .utf8)
        _ = try FileManager.default.replaceItemAt(file, withItemAt: temporary)
    }

    /// Renames the original away and creates a new file in its place — vim with
    /// its default `backupcopy=no`.
    private func saveViaBackup(_ file: URL, _ content: String) throws {
        let backup = file.appendingPathExtension("bak")
        try? FileManager.default.removeItem(at: backup)
        try FileManager.default.moveItem(at: file, to: backup)
        try content.write(to: file, atomically: false, encoding: .utf8)
        try? FileManager.default.removeItem(at: backup)
    }

    private func makeFile(_ content: String = "# v0") throws -> URL {
        let file = tempDirectory.appendingPathComponent("doc.md")
        try content.write(to: file, atomically: false, encoding: .utf8)
        return file
    }

    /// Counts change notifications, since the watcher coalesces bursts.
    private func expectChange(count: Int = 1) -> XCTestExpectation {
        let expectation = expectation(description: "file change reported")
        expectation.expectedFulfillmentCount = count
        sut.onChange = { expectation.fulfill() }
        return expectation
    }

    // MARK: - Reload fires on every save, whichever way the editor writes

    func test_onChange_repeatedInPlaceSaves_firesEveryTime() throws {
        // Arrange
        let file = try makeFile()
        sut.start(url: file)

        // Act
        for round in 1 ... 3 {
            let changed = expectChange()
            try saveInPlace(file, "# v\(round)")

            // Assert
            wait(for: [changed], timeout: 5)
        }
    }

    /// The original bug: an atomic save replaces the inode, so a descriptor
    /// opened on the old one stops receiving events after the first save.
    func test_onChange_repeatedAtomicSaves_firesEveryTime() throws {
        // Arrange
        let file = try makeFile()
        sut.start(url: file)

        // Act
        for round in 1 ... 3 {
            let changed = expectChange()
            try saveAtomically(file, "# v\(round)")

            // Assert
            wait(for: [changed], timeout: 5)
        }
    }

    func test_onChange_repeatedBackupRenameSaves_firesEveryTime() throws {
        // Arrange
        let file = try makeFile()
        sut.start(url: file)

        // Act
        for round in 1 ... 3 {
            let changed = expectChange()
            try saveViaBackup(file, "# v\(round)")

            // Assert
            wait(for: [changed], timeout: 5)
        }
    }

    // MARK: - Content is current when the change is reported

    func test_onChange_afterAtomicSave_readsUpdatedContent() throws {
        // Arrange
        let file = try makeFile("# old")
        var readBack: String?
        let changed = expectation(description: "second save reported")
        sut.onChange = {
            readBack = try? String(contentsOf: file, encoding: .utf8)
            if readBack == "# newest" { changed.fulfill() }
        }
        sut.start(url: file)

        // Act
        try saveAtomically(file, "# newer")
        try saveAtomically(file, "# newest")

        // Assert
        wait(for: [changed], timeout: 5)
        XCTAssertEqual(readBack, "# newest")
    }

    // MARK: - Files that disappear and come back

    func test_onChange_fileDeletedAndRecreated_keepsReporting() throws {
        // Arrange
        let file = try makeFile()
        sut.start(url: file)

        let recreated = expectChange()
        try FileManager.default.removeItem(at: file)
        try "# recreated".write(to: file, atomically: false, encoding: .utf8)
        wait(for: [recreated], timeout: 5)

        // Act
        let changed = expectChange()
        try saveInPlace(file, "# after recreation")

        // Assert
        wait(for: [changed], timeout: 5)
    }

    /// A branch switch or a cloud sync can keep the file away for seconds. The
    /// directory is watched precisely because a path that does not exist cannot
    /// be watched itself.
    func test_onChange_fileReturnsAfterLongAbsence_isReported() throws {
        // Arrange
        let file = try makeFile()
        sut.start(url: file)

        let removed = expectChange()
        try FileManager.default.removeItem(at: file)
        wait(for: [removed], timeout: 5)

        // Act — far longer than any fixed retry budget would allow
        Thread.sleep(forTimeInterval: 4)
        let returned = expectChange()
        try "# back again".write(to: file, atomically: false, encoding: .utf8)

        // Assert
        wait(for: [returned], timeout: 5)
    }

    // MARK: - Lifecycle

    /// Callers read the file and then start watching, so an attach that took
    /// effect asynchronously would miss a write landing in between.
    func test_start_writeImmediatelyAfterwards_isNotMissed() throws {
        // Arrange
        let file = try makeFile()
        sut.start(url: file)
        let changed = expectChange()

        // Act — no pause between start() and the write
        try saveInPlace(file, "# right after start")

        // Assert
        wait(for: [changed], timeout: 5)
    }

    func test_stop_afterwardsChangesAreNotReported() throws {
        // Arrange
        let file = try makeFile()
        var reported = false
        sut.onChange = { reported = true }
        sut.start(url: file)

        // Act
        sut.stop()
        try saveInPlace(file, "# after stop")

        // Assert
        let settled = expectation(description: "waited past the debounce")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { settled.fulfill() }
        wait(for: [settled], timeout: 5)
        XCTAssertFalse(reported)
    }

    /// Switching documents while a save is in flight must not leave the watcher
    /// attached to the previous file.
    func test_start_switchingDocumentDuringAtomicSave_watchesOnlyTheNewFile() throws {
        // Arrange
        let fileA = tempDirectory.appendingPathComponent("a.md")
        let fileB = tempDirectory.appendingPathComponent("b.md")
        try "# A".write(to: fileA, atomically: false, encoding: .utf8)
        try "# B".write(to: fileB, atomically: false, encoding: .utf8)

        sut.start(url: fileA)
        try saveAtomically(fileA, "# A changed")

        // Act — the document switches while the save is still settling
        sut.stop()
        sut.start(url: fileB)

        var reported = false
        let settled = expectation(description: "waited past the debounce")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.sut.onChange = { reported = true }
            try? self.saveAtomically(fileA, "# A again")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { settled.fulfill() }
        }

        // Assert — touching A must not wake a watcher pointed at B
        wait(for: [settled], timeout: 10)
        XCTAssertFalse(reported)
    }

    func test_startStopCycles_doNotLeakFileDescriptors() throws {
        // Arrange
        let file = try makeFile()
        sut.start(url: file)
        sut.stop()

        let settled = expectation(description: "cancel handlers drained")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { settled.fulfill() }
        wait(for: [settled], timeout: 5)
        let baseline = openFileDescriptorCount()

        // Act
        for _ in 0 ..< 30 {
            sut.start(url: file)
            sut.stop()
        }
        let drained = expectation(description: "cancel handlers drained again")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { drained.fulfill() }
        wait(for: [drained], timeout: 5)

        // Assert — a couple of descriptors of slack for unrelated activity
        XCTAssertLessThanOrEqual(openFileDescriptorCount(), baseline + 2)
    }

    private func openFileDescriptorCount() -> Int {
        (Int32(0) ..< Int32(256)).filter { fcntl($0, F_GETFD) != -1 }.count
    }
}
