import SwiftUI
import AppKit

struct MenuBarView: View {
    @State private var appState = AppStateManager.shared
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Status indicator
            HStack(spacing: 8) {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                Text(statusText)
                    .font(.system(size: 13, weight: .medium))
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Divider()

            Button("History…") {
                AppDelegateLocator.shared?.showHistory()
            }

            Button("Preferences…") {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            Button("Quit VoiceFlow") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(.bottom, 8)
    }

    private var statusIcon: String {
        switch appState.state {
        case .idle: return "mic"
        case .recording: return "mic.fill"
        case .transcribing: return "waveform"
        case .postProcessing: return "sparkles"
        case .showingResult: return "checkmark.circle"
        case .error: return "exclamationmark.triangle"
        }
    }

    private var statusColor: Color {
        switch appState.state {
        case .idle: return .secondary
        case .recording: return .red
        case .transcribing, .postProcessing: return .blue
        case .showingResult: return .green
        case .error: return .red
        }
    }

    private var statusText: String {
        switch appState.state {
        case .idle:
            return appState.recordingMode == .vadToggle
                ? "Ready — press \(appState.hotkeyOption.displayName) to record"
                : "Ready — hold \(appState.hotkeyOption.displayName) to record"
        case .recording: return "Recording…"
        case .transcribing: return "Transcribing…"
        case .postProcessing: return "Cleaning up…"
        case .showingResult: return "Done"
        case .error(let msg): return "Error: \(msg)"
        }
    }
}
