import SwiftUI
import AppKit

struct FloatingPanelView: View {
    @State var appState: AppStateManager
    weak var panel: FloatingPanel?

    // Progressive word reveal state
    @State private var revealedWords: [String] = []
    @State private var wordTimer: Timer?
    @State private var dismissTimer: Timer?

    var body: some View {
        ZStack {
            switch appState.state {
            case .idle:
                EmptyView()

            case .recording:
                PillCard {
                    HStack(spacing: 12) {
                        WaveformView()
                        Text(appState.recordingMode == .vadToggle ? "Recording (auto-stop)…" : "Recording…")
                            .font(.system(size: 16, weight: .medium, design: .default))
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))

            case .transcribing:
                PillCard {
                    HStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Transcribing…")
                            .font(.system(size: 16, weight: .medium, design: .default))
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))

            case .postProcessing:
                PillCard {
                    HStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Cleaning up…")
                            .font(.system(size: 16, weight: .medium, design: .default))
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))

            case .showingResult(let result):
                PillCard {
                    Text(revealedWords.joined(separator: " "))
                        .font(.system(size: 16, weight: .medium, design: .default))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: 560, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .onTapGesture {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(result.text, forType: .string)
                        }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .onAppear {
                    startWordReveal(result: result)
                }
                .onDisappear {
                    stopTimers()
                }

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
                .onAppear {
                    scheduleDismiss(after: 5)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: stateKey)
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
        .onChange(of: stateKey) { _, newKey in
            if newKey == "idle" {
                panel?.hide()
            } else {
                panel?.show()
                revealedWords = []
                stopTimers()
            }
        }
    }

    private var stateKey: String {
        switch appState.state {
        case .idle: return "idle"
        case .recording: return "recording"
        case .transcribing: return "transcribing"
        case .postProcessing: return "postProcessing"
        case .showingResult: return "result"
        case .error: return "error"
        }
    }

    private func startWordReveal(result: DictationResult) {
        guard !result.words.isEmpty else {
            revealedWords = result.text.components(separatedBy: " ").filter { !$0.isEmpty }
            scheduleDismiss(after: 3)
            return
        }

        revealedWords = []
        var wordIndex = 0
        let startTime = Date()

        wordTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
            guard wordIndex < result.words.count else {
                timer.invalidate()
                self.scheduleDismiss(after: 3)
                return
            }

            let elapsed = Float(Date().timeIntervalSince(startTime))
            while wordIndex < result.words.count && result.words[wordIndex].start <= elapsed {
                self.revealedWords.append(result.words[wordIndex].word)
                wordIndex += 1
            }
        }
    }

    private func scheduleDismiss(after seconds: TimeInterval) {
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in
            Task { @MainActor in
                self.dismiss()
            }
        }
    }

    private func stopTimers() {
        wordTimer?.invalidate()
        wordTimer = nil
        dismissTimer?.invalidate()
        dismissTimer = nil
    }

    private func dismiss() {
        stopTimers()
        Task { @MainActor in
            appState.state = .idle
        }
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
        .onAppear { phase = true }
        .onDisappear { phase = false }
    }
}
