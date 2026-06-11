import Foundation

/// Watches one directory for content changes via a kqueue DispatchSource and
/// fires a debounced callback. Powers `.folderChanged` background agents
/// ("watch Downloads and organize new files"). Lightweight: one fd per folder,
/// no polling.
final class FolderWatcher {
    private let path: String
    private let debounce: TimeInterval
    private let onChange: () -> Void

    private var fd: Int32 = -1
    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?
    private let queue = DispatchQueue(label: "aria.folderwatcher")

    init(path: String, debounce: TimeInterval = 2.0, onChange: @escaping () -> Void) {
        self.path = (path as NSString).expandingTildeInPath
        self.debounce = debounce
        self.onChange = onChange
    }

    /// Begin watching. False when the folder can't be opened (missing/no access).
    @discardableResult
    func start() -> Bool {
        stop()
        fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return false }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: queue)
        src.setEventHandler { [weak self] in self?.scheduleFire() }
        src.setCancelHandler { [fd] in close(fd) }
        src.resume()
        source = src
        return true
    }

    func stop() {
        pending?.cancel()
        pending = nil
        source?.cancel()   // cancel handler closes the fd
        source = nil
        fd = -1
    }

    /// Collapse bursts (a download writes many events) into one fire.
    private func scheduleFire() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        pending = work
        queue.asyncAfter(deadline: .now() + debounce, execute: work)
    }

    deinit { stop() }
}
