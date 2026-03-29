import SwiftUI
import AppKit

struct FloatingPanelView: View {
    @State var appState: AppStateManager
    weak var panel: FloatingPanel?

    @State private var dismissTimer: Timer?

    var body: some View {
        ZStack {
            // Source-switched notification (shown while state is idle)
            if let notification = appState.sourceNotification {
                PillCard {
                    HStack(spacing: 10) {
                        Image(systemName: appState.audioSource == .microphone ? "mic.fill" : "speaker.wave.2.fill")
                            .foregroundStyle(.blue)
                        Text("Source: \(notification)")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            switch appState.state {
            case .idle:
                EmptyView()

            case .recording:
                PillCard {
                    HStack(spacing: 12) {
                        WaveformView()
                        Text(recordingLabel)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))

            case .transcribing:
                PillCard {
                    HStack(spacing: 12) {
                        ProgressView().controlSize(.small)
                        Text("Transcribing…")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))

            case .postProcessing:
                PillCard {
                    HStack(spacing: 12) {
                        ProgressView().controlSize(.small)
                        Text("Cleaning up…")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))

            case .showingResult:
                PillCard {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Transcribed & pasted")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .onAppear { scheduleDismiss(after: 2) }
                .onDisappear { cancelDismiss() }

            case .error(let message):
                PillCard {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(message)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                }
                .transition(.opacity)
                .onAppear { scheduleDismiss(after: 5) }
                .onDisappear { cancelDismiss() }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: stateKey)
        .animation(.easeInOut(duration: 0.2), value: appState.sourceNotification != nil)
        .onKeyPress(.escape) { dismiss(); return .handled }
        .onChange(of: stateKey) { _, newKey in
            if newKey == "idle" {
                panel?.hide()
            } else {
                panel?.show()
            }
        }
        .onChange(of: appState.sourceNotification) { _, newValue in
            if newValue != nil {
                panel?.show()
            } else if case .idle = appState.state {
                panel?.hide()
            }
        }
    }

    // MARK: - Helpers

    private var recordingLabel: String {
        if appState.audioSource == .systemAudio {
            return "Recording — press \(appState.recordingHotkey.displayName) to stop"
        }
        return appState.recordingMode == .vadToggle ? "Recording (auto-stop)…" : "Recording…"
    }

    private var stateKey: String {
        switch appState.state {
        case .idle:           return "idle"
        case .recording:      return "recording"
        case .transcribing:   return "transcribing"
        case .postProcessing: return "postProcessing"
        case .showingResult:  return "result"
        case .error:          return "error"
        }
    }

    private func scheduleDismiss(after seconds: TimeInterval) {
        cancelDismiss()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in
            Task { @MainActor in self.dismiss() }
        }
    }

    private func cancelDismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil
    }

    private func dismiss() {
        cancelDismiss()
        Task { @MainActor in appState.state = .idle }
    }
}

// MARK: - Pill card container

struct PillCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
            }
    }
}

// MARK: - Animated waveform

struct WaveformView: View {
    @State private var phase = false

    private let barHeights: [CGFloat] = [8, 16, 24, 16, 8]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barHeights.count, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(.red)
                    .frame(width: 3, height: phase ? barHeights[i] : 4)
                    .animation(
                        .easeInOut(duration: 0.4)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.08),
                        value: phase
                    )
            }
        }
        .frame(height: 28)
        .onAppear  { phase = true  }
        .onDisappear { phase = false }
    }
}
