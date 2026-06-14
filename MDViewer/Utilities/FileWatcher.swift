import Foundation

final class FileWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var debounceTimer: DispatchWorkItem?
    private let debounceDelay: TimeInterval = 0.5
    private let queue = DispatchQueue(label: "com.mdviewer.filewatcher", qos: .utility)

    var onChange: (() -> Void)?

    func start(url: URL) {
        stop()

        fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor != -1 else { return }

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete],
            queue: queue
        )

        source?.setEventHandler { [weak self] in
            self?.scheduleReload()
        }

        source?.setCancelHandler { [weak self] in
            guard let self else { return }
            if fileDescriptor != -1 {
                close(fileDescriptor)
                fileDescriptor = -1
            }
        }

        source?.resume()
    }

    func stop() {
        debounceTimer?.cancel()
        debounceTimer = nil
        source?.cancel()
        source = nil
    }

    private func scheduleReload() {
        debounceTimer?.cancel()
        let item = DispatchWorkItem { [weak self] in
            DispatchQueue.main.async {
                self?.onChange?()
            }
        }
        debounceTimer = item
        queue.asyncAfter(deadline: .now() + debounceDelay, execute: item)
    }

    deinit {
        stop()
    }
}
