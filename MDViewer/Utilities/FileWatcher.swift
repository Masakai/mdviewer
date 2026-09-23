import Foundation

final class FileWatcher {
    private let queue = DispatchQueue(label: "com.mdviewer.filewatcher", qos: .utility)
    private let debounceDelay: TimeInterval = 0.5

    // start()/stop() are called from the main actor while events and re-attach
    // retries run on `queue`, so every access to the state below is serialised
    // by this lock. Without it a re-attach in flight could overwrite the source
    // installed by a concurrent start(), leaking its descriptor and leaving the
    // new file unwatched.
    //
    // A lock rather than dispatching onto the queue, because start() must take
    // effect synchronously: callers read the file and then start watching, so an
    // asynchronous attach would miss any write landing in between.
    private let lock = NSLock()

    /// Watches the file itself: the only way to see in-place writes, which do not
    /// touch the containing directory.
    private var fileSource: DispatchSourceFileSystemObject?

    /// Watches the containing directory, which usually outlives the file. It
    /// reports the file being removed and, crucially, coming back: a path that
    /// does not exist cannot be watched, so without this there is nothing left
    /// to notice a branch switch or a cloud sync restoring it.
    ///
    /// This is one extra level, not a general answer: a directory descriptor is
    /// bound to an inode just like a file's, so deleting the directory itself
    /// (removing the whole checkout, say) orphans this source too. Watching the
    /// parent, and its parent, would only push the same problem further up, so
    /// recovery from that case is left to reopening the document.
    private var directorySource: DispatchSourceFileSystemObject?

    private var debounceTimer: DispatchWorkItem?

    /// The path being watched. Retained so the watcher can re-attach to the same
    /// path after an editor's atomic save replaces the inode.
    private var watchedURL: URL?

    /// Whether the file existed at the last check, so a directory event can tell
    /// "the file came back" from unrelated churn among its siblings.
    private var fileExisted = false

    var onChange: (() -> Void)?

    func start(url: URL) {
        lock.lock()
        defer { lock.unlock() }
        tearDownLocked()
        watchedURL = url
        fileExisted = attachFileLocked(url: url)
        attachDirectoryLocked(for: url)
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        tearDownLocked()
    }

    /// Tears down both sources. The caller must hold `lock`.
    private func tearDownLocked() {
        debounceTimer?.cancel()
        debounceTimer = nil
        watchedURL = nil
        fileExisted = false
        fileSource?.cancel()
        fileSource = nil
        directorySource?.cancel()
        directorySource = nil
    }

    /// Attaches a DispatchSource to the given path. The caller must hold `lock`.
    /// - Returns: false if the file could not be opened, i.e. it does not exist.
    @discardableResult
    private func attachFileLocked(url: URL) -> Bool {
        fileSource?.cancel()
        fileSource = nil

        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor != -1 else { return false }

        let newSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .rename, .delete],
            queue: queue
        )

        newSource.setEventHandler { [weak self, weak newSource] in
            guard let self, let mask = newSource?.data else { return }
            handleFileEvent(mask: mask)
        }

        // Close the descriptor captured in this local constant, not the instance
        // property: a rapid stop() -> start() sequence would otherwise let this
        // handler close the *next* descriptor, killing the new watcher outright
        // or leaking the old fd.
        newSource.setCancelHandler {
            close(descriptor)
        }

        fileSource = newSource
        newSource.resume()
        return true
    }

    /// Watches the directory containing the file. The caller must hold `lock`.
    private func attachDirectoryLocked(for url: URL) {
        directorySource?.cancel()
        directorySource = nil

        let directory = url.deletingLastPathComponent()
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor != -1 else { return }

        let newSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .delete, .rename],
            queue: queue
        )

        newSource.setEventHandler { [weak self] in
            self?.handleDirectoryEvent()
        }

        newSource.setCancelHandler {
            close(descriptor)
        }

        directorySource = newSource
        newSource.resume()
    }

    /// Handles an event on the file itself.
    ///
    /// Most editors (VS Code, vim, NSDocument) and this app's own `save()`
    /// (`atomically: true`) perform an atomic save: they write a temporary file
    /// and rename it over the original, which replaces the inode. The original
    /// descriptor is then left pointing at an orphaned inode and no further
    /// event is ever delivered, so rename/delete must re-attach to the path.
    private func handleFileEvent(mask: DispatchSource.FileSystemEvent) {
        lock.lock()
        defer { lock.unlock() }

        // A stop() may have run between this event firing and the lock being
        // acquired, in which case there is nothing left to watch or report.
        guard let url = watchedURL else { return }

        if mask.contains(.rename) || mask.contains(.delete) {
            // Re-open immediately: after an atomic save the replacement is
            // already in place. If it is not, the directory source will pick the
            // file up whenever it reappears — however long that takes.
            fileExisted = attachFileLocked(url: url)
        }
        scheduleReloadLocked()
    }

    /// Handles an event on the containing directory.
    ///
    /// The directory churns for all sorts of unrelated reasons, so this only
    /// acts on the file appearing or disappearing — the transitions the file
    /// source cannot report, because a path that does not exist cannot be
    /// watched at all.
    private func handleDirectoryEvent() {
        lock.lock()
        defer { lock.unlock() }

        guard let url = watchedURL else { return }

        let existsNow = FileManager.default.fileExists(atPath: url.path)
        guard existsNow != fileExisted else { return }

        fileExisted = existsNow
        if existsNow {
            // The file came back (branch switch, cloud sync, delete + recreate):
            // re-attach and reload, since no file event announced its return.
            attachFileLocked(url: url)
        }
        scheduleReloadLocked()
    }

    /// The caller must hold `lock`.
    private func scheduleReloadLocked() {
        debounceTimer?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // Read the callback under the lock so a concurrent stop() cannot be
            // followed by a stale notification.
            lock.lock()
            let handler = watchedURL != nil ? onChange : nil
            lock.unlock()
            guard let handler else { return }
            DispatchQueue.main.async { handler() }
        }
        debounceTimer = item
        queue.asyncAfter(deadline: .now() + debounceDelay, execute: item)
    }

    deinit {
        // Cancel directly: dispatching onto the queue here would capture a
        // self that is already being deallocated. The cancel handler closes the
        // descriptor, and no further events can be delivered once cancelled.
        debounceTimer?.cancel()
        fileSource?.cancel()
        directorySource?.cancel()
    }
}
