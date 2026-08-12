import Foundation

@MainActor
public final class HistoryStore: ObservableObject {
    public static let shared = HistoryStore()

    @Published public private(set) var entries: [HistoryEntry] = []

    private let storageURL: URL
    private static let ttl: TimeInterval = 24 * 60 * 60

    private init() {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support")
        let dir = support.appendingPathComponent("KyroVoice")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        storageURL = dir.appendingPathComponent("history.json")
        load()
    }

    /// In-memory store for `--snapshot`, so rendering the history window for the
    /// docs cannot touch the real history.json.
    init(sample: [HistoryEntry]) {
        storageURL = URL(fileURLWithPath: "/dev/null")
        entries = sample
    }

    public func add(_ entry: HistoryEntry) {
        entries.insert(entry, at: 0)
        prune()
        save()
    }

    public func clear() {
        entries.removeAll()
        save()
    }

    private func prune() {
        let cutoff = Date().addingTimeInterval(-Self.ttl)
        entries = entries.filter { $0.timestamp > cutoff }
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        entries = (try? decoder.decode([HistoryEntry].self, from: data)) ?? []
        prune()
    }

    /// Re-applies the 24 h TTL. Call before showing history: pruning only on
    /// `add` meant that after a quiet day the window still listed stale entries.
    public func pruneNow() {
        prune()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(entries) else { return }
        // Off the main actor: this ran synchronously right after injection,
        // hitching the UI exactly as the "injected" checkmark animated.
        let url = storageURL
        Task.detached(priority: .utility) {
            try? data.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: url.path
            )
        }
    }
}
