import SwiftUI
import AppKit

struct HistoryView: View {
    @State var store: HistoryStore
    @State private var searchText = ""
    @State private var selectedEntry: HistoryEntry?

    private var filtered: [HistoryEntry] {
        if searchText.isEmpty { return store.entries }
        return store.entries.filter {
            $0.text.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationSplitView {
            List(filtered, selection: $selectedEntry) { entry in
                HistoryRow(entry: entry)
                    .tag(entry)
                    .contextMenu {
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(entry.text, forType: .string)
                        }
                        Button("Delete", role: .destructive) {
                            if selectedEntry?.id == entry.id { selectedEntry = nil }
                            store.delete(entry)
                        }
                    }
            }
            .searchable(text: $searchText, prompt: "Search transcriptions")
            .toolbar {
                ToolbarItem(placement: .destructiveAction) {
                    Button("Clear All") { store.clearAll(); selectedEntry = nil }
                        .disabled(store.entries.isEmpty)
                }
            }
        } detail: {
            if let entry = selectedEntry {
                HistoryDetailView(entry: entry)
            } else {
                Text("Select a transcription")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Row

private struct HistoryRow: View {
    let entry: HistoryEntry

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.text)
                .lineLimit(2)
                .font(.system(size: 13))
            HStack(spacing: 6) {
                Text(Self.timeFmt.string(from: entry.timestamp))
                Text(entry.language.uppercased())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                if entry.source == "system" {
                    Image(systemName: "speaker.wave.2")
                        .font(.caption2)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Detail

private struct HistoryDetailView: View {
    let entry: HistoryEntry

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .medium
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(Self.timeFmt.string(from: entry.timestamp))
                    .font(.headline)
                Spacer()
                Text(entry.language.uppercased())
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                Text(String(format: "%.1fs", entry.duration))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                Text(entry.text)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.text, forType: .string)
                }
                ExportMenuButton(entry: entry)
            }
        }
        .padding()
    }
}

// MARK: - Export menu (placeholder, wired in Feature 2)

struct ExportMenuButton: View {
    let entry: HistoryEntry

    var body: some View {
        Menu("Export") {
            Button("Markdown (.md)") { ExportEngine.saveSingle(entry, format: .markdown) }
            Button("Plain Text (.txt)") { ExportEngine.saveSingle(entry, format: .plainText) }
            Button("JSON (.json)") { ExportEngine.saveSingle(entry, format: .json) }
        }
    }
}
