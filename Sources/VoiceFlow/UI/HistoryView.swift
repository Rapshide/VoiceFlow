import SwiftUI
import AppKit

struct HistoryView: View {
    @State var store: HistoryStore
    @State private var searchText = ""
    @State private var selectedEntry: HistoryEntry?
    @FocusState private var isSearchFocused: Bool

    private var filtered: [HistoryEntry] {
        if searchText.isEmpty { return store.entries }
        return store.entries.filter {
            $0.text.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                // Custom search field — avoids NavigationSplitView layout instability
                // caused by the built-in .searchable modifier.
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search transcriptions", text: $searchText)
                        .textFieldStyle(.plain)
                        .focused($isSearchFocused)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            isSearchFocused = true
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color(nsColor: .controlBackgroundColor))

                Divider()

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
                .listStyle(.sidebar)
                .toolbar {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Clear All") { store.clearAll(); selectedEntry = nil }
                            .disabled(store.entries.isEmpty)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            if let entry = selectedEntry {
                HistoryDetailView(entry: entry)
            } else {
                Text("Select a transcription")
                    .foregroundStyle(.secondary)
            }
        }
        // Auto-focus the search bar when the window opens or is brought to front.
        .onReceive(NotificationCenter.default.publisher(for: .historyFocusSearch)) { _ in
            isSearchFocused = true
        }
        // Redirect typing that occurred before the search field had focus.
        .onReceive(NotificationCenter.default.publisher(for: .historyTypeCharacter)) { note in
            guard let chars = note.object as? String else { return }
            searchText += chars
            isSearchFocused = true
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

// MARK: - Export menu

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
