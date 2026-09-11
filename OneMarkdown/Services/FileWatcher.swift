import Foundation

/// 用 DispatchSource 监听单个文件或目录。
/// 文件被原子替换（rename/delete）后自动轮询重挂；事件回调在主线程。
@MainActor
final class FileWatcher {
    enum Event: Sendable {
        /// 内容被写入
        case modified
        /// 原路径被替换/重建，已重新挂载监听
        case recreated
        /// 原路径消失且短时间内未回来
        case removed
    }

    let url: URL
    private let isDirectory: Bool
    private let debounceInterval: Duration
    private let onEvent: (Event) -> Void

    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1
    private var debounceTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var stopped = false

    init(url: URL, isDirectory: Bool, debounce: Duration = .milliseconds(150), onEvent: @escaping (Event) -> Void) {
        self.url = url
        self.isDirectory = isDirectory
        self.debounceInterval = debounce
        self.onEvent = onEvent
    }

    deinit {
        // deinit 不在 MainActor 上，只能直接释放句柄；source 取消时会关闭 fd
        source?.cancel()
    }

    /// 返回是否成功挂载。
    @discardableResult
    func start() -> Bool {
        stopped = false
        return attach()
    }

    func stop() {
        stopped = true
        debounceTask?.cancel(); debounceTask = nil
        pollTask?.cancel(); pollTask = nil
        detach()
    }

    // MARK: - 内部

    private func attach() -> Bool {
        detach()
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return false }
        fd = descriptor
        let mask: DispatchSource.FileSystemEvent = isDirectory
            ? [.write, .delete, .rename]
            : [.write, .extend, .delete, .rename, .attrib]
        // 直接用主队列，回调即在主线程，避免跨线程访问状态
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: mask, queue: .main)
        src.setEventHandler { [weak self] in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.handle(events: src.data)
            }
        }
        src.setCancelHandler {
            close(descriptor)
        }
        src.resume()
        source = src
        return true
    }

    private func detach() {
        source?.cancel()
        source = nil
        fd = -1
    }

    private func handle(events: DispatchSource.FileSystemEvent) {
        guard !stopped else { return }
        if events.contains(.delete) || events.contains(.rename) {
            // 编辑器安全写入（先写临时文件再 rename 覆盖）会走到这里；原 fd 已指向旧 inode
            detach()
            startPolling()
            return
        }
        scheduleModified()
    }

    private func scheduleModified() {
        debounceTask?.cancel()
        let interval = debounceInterval
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled, let self, !self.stopped else { return }
            self.onEvent(.modified)
        }
    }

    /// 每 100 ms 检查一次路径是否回来，最多 2 s；之后降为每 2 s 一次直到回来或 stop。
    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            var elapsed: Duration = .zero
            var reportedRemoved = false
            while !Task.isCancelled {
                guard let self, !self.stopped else { return }
                if FileManager.default.fileExists(atPath: self.url.path) {
                    if self.attach() {
                        self.onEvent(.recreated)
                        return
                    }
                }
                if !reportedRemoved && elapsed >= .seconds(2) {
                    reportedRemoved = true
                    self.onEvent(.removed)
                }
                let step: Duration = reportedRemoved ? .seconds(2) : .milliseconds(100)
                try? await Task.sleep(for: step)
                elapsed += step
            }
        }
    }
}
