import Foundation
import Observation

@Observable
@MainActor
final class HistoryStore {
    private(set) var entries: [HistoryEntry] = []
    private static let maxEntries = 500

    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("VoiceFlow", isDirectory: true)
        return base.appendingPathComponent("history.json")
    }

    init() {
        load()
    }

    func add(_ result: DictationResult, language: String, source: String = "mic") {
        let entry = HistoryEntry(
            text: result.text,
            language: language,
            duration: result.duration,
            source: source
        )
        entries.insert(entry, at: 0)
        if entries.count > Self.maxEntries {
            entries = Array(entries.prefix(Self.maxEntries))
        }
        save()
    }

    func delete(_ entry: HistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func clearAll() {
        entries.removeAll()
        save()
    }

    private func load() {
        let url = Self.fileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            entries = try decoder.decode([HistoryEntry].self, from: data)
        } catch {
            print("HistoryStore: failed to load: \(error)")
        }
    }

    private func save() {
        let url = Self.fileURL
        do {
            let dir = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(entries)
            try data.write(to: url, options: .atomic)
        } catch {
            print("HistoryStore: failed to save: \(error)")
        }
    }
}
