import Foundation
import CoreServices

/// Watches the vault directory for filesystem changes to `.md` notes, coalesced and
/// delivered on a dispatch queue. Changes that match our own recent `Vault.writeAtomically`
/// calls are filtered out via `Vault.wasSelfWrite`, so the repaint loop can't race with
/// itself under fast typing (a bare debounce is not enough for that — see ROADMAP).
public final class VaultWatcher {
    public typealias ChangeHandler = ([URL]) -> Void

    private let vault: Vault
    private let queue: DispatchQueue
    private let onChange: ChangeHandler
    private var stream: FSEventStreamRef?

    public init(
        vault: Vault,
        queue: DispatchQueue = DispatchQueue(label: "dev.jonany.foolscap.vaultwatcher"),
        onChange: @escaping ChangeHandler
    ) {
        self.vault = vault
        self.queue = queue
        self.onChange = onChange
    }

    public func start() {
        guard stream == nil else { return }

        let pathsToWatch = [vault.root.path] as CFArray
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, clientCallBackInfo, numEvents, eventPaths, _, _ in
            guard let clientCallBackInfo else { return }
            let watcher = Unmanaged<VaultWatcher>.fromOpaque(clientCallBackInfo).takeUnretainedValue()
            let cfArray = unsafeBitCast(eventPaths, to: CFArray.self) as NSArray
            guard let paths = cfArray as? [String] else { return }
            watcher.handleEvents(paths: paths)
        }

        guard let newStream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.2, // coalesce rapid saves (e.g. an editor's autosave) into one repaint
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        ) else { return }

        stream = newStream
        FSEventStreamSetDispatchQueue(newStream, queue)
        FSEventStreamStart(newStream)
    }

    public func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit { stop() }

    private func handleEvents(paths: [String]) {
        let changed = paths
            .map { URL(fileURLWithPath: $0) }
            .filter { $0.pathExtension.lowercased() == "md" }
            .filter { !vault.wasSelfWrite(path: $0.path) }
        guard !changed.isEmpty else { return }
        onChange(changed)
    }
}
