import Foundation

struct HistoryEntry: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let text: String
    let language: String
    let duration: TimeInterval
    let timestamp: Date
    var source: String // "mic" or "system"

    init(text: String, language: String, duration: TimeInterval, source: String = "mic") {
        self.id = UUID()
        self.text = text
        self.language = language
        self.duration = duration
        self.timestamp = Date()
        self.source = source
    }
}
