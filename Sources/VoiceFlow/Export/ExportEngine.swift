import AppKit
import Foundation

enum ExportFormat: String, CaseIterable {
    case markdown = "Markdown"
    case plainText = "Plain Text"
    case json = "JSON"

    var fileExtension: String {
        switch self {
        case .markdown: return "md"
        case .plainText: return "txt"
        case .json: return "json"
        }
    }
}

@MainActor
enum ExportEngine {

    // MARK: - Single entry

    static func saveSingle(_ entry: HistoryEntry, format: ExportFormat) {
        let content: String
        let defaultName: String

        switch format {
        case .markdown:
            content = markdown(for: entry)
            defaultName = "transcription-\(fileTimestamp(entry.timestamp)).md"
        case .plainText:
            content = entry.text
            defaultName = "transcription-\(fileTimestamp(entry.timestamp)).txt"
        case .json:
            content = jsonString(for: [entry])
            defaultName = "transcription-\(fileTimestamp(entry.timestamp)).json"
        }

        saveWithPanel(content: content, defaultName: defaultName, fileExtension: format.fileExtension)
    }

    // MARK: - Batch export

    static func saveBatch(_ entries: [HistoryEntry], format: ExportFormat) {
        guard !entries.isEmpty else { return }
        let content: String
        let defaultName: String

        switch format {
        case .markdown:
            content = entries.map { markdown(for: $0) }.joined(separator: "\n\n---\n\n")
            defaultName = "transcriptions-\(fileTimestamp(Date())).md"
        case .plainText:
            content = entries.map { entry in
                "[\(displayTimestamp(entry.timestamp))] \(entry.text)"
            }.joined(separator: "\n\n")
            defaultName = "transcriptions-\(fileTimestamp(Date())).txt"
        case .json:
            content = jsonString(for: entries)
            defaultName = "transcriptions-\(fileTimestamp(Date())).json"
        }

        saveWithPanel(content: content, defaultName: defaultName, fileExtension: format.fileExtension)
    }

    // MARK: - Formatters

    private static func markdown(for entry: HistoryEntry) -> String {
        """
        ## \(displayTimestamp(entry.timestamp))

        \(entry.text)

        *Language: \(entry.language.uppercased()) | Duration: \(String(format: "%.1fs", entry.duration)) | Source: \(entry.source)*
        """
    }

    private static func jsonString(for entries: [HistoryEntry]) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(entries),
              let str = String(data: data, encoding: .utf8) else { return "[]" }
        return str
    }

    private static let displayFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .medium
        return f
    }()

    private static func displayTimestamp(_ date: Date) -> String {
        displayFmt.string(from: date)
    }

    private static func fileTimestamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f.string(from: date)
    }

    // MARK: - Save panel

    private static func saveWithPanel(content: String, defaultName: String, fileExtension: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultName
        panel.allowedContentTypes = [.init(filenameExtension: fileExtension) ?? .plainText]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            print("ExportEngine: failed to write: \(error)")
        }
    }
}
