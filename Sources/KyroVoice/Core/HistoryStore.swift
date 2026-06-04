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

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: storageURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: storageURL.path)
    }
}
