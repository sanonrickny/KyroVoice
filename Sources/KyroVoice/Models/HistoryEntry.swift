import Foundation

public struct HistoryEntry: Identifiable, Codable {
    public let id: UUID
    public let timestamp: Date
    public let text: String
    public let mode: DictationMode
    public let targetAppName: String?
}
