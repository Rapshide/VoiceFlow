import SwiftUI

@main
struct VoiceFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
        } label: {
            MenuBarIcon()
        }

        Settings {
            SettingsView()
        }
    }
}

struct MenuBarIcon: View {
    @State private var appState = AppStateManager.shared

    var body: some View {
        Image(systemName: iconName)
            .symbolRenderingMode(.hierarchical)
    }

    private var iconName: String {
        switch appState.state {
        case .idle: return "mic"
        case .recording: return "mic.fill"
        case .transcribing: return "waveform"
        case .postProcessing: return "sparkles"
        case .showingResult: return "checkmark.circle"
        case .error: return "exclamationmark.triangle"
        }
    }
}
