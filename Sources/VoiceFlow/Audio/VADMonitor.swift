import Foundation
import WhisperKit

@MainActor
final class VADMonitor {
    private let vad: EnergyVAD
    private var timer: Timer?
    private weak var source: (any AudioSourceProtocol)?

    /// Seconds of continuous silence before firing
    var silenceTimeout: Double = 1.5

    /// Called on the main actor when silence exceeds `silenceTimeout`
    var onSilenceDetected: (() -> Void)?

    private var silenceStart: Date?

    init() {
        // 100ms frames at 16kHz, energy threshold 0.02
        self.vad = EnergyVAD(
            sampleRate: 16000,
            frameLength: 0.1,
            frameOverlap: 0.0,
            energyThreshold: 0.02
        )
    }

    func start(source: any AudioSourceProtocol, silenceTimeout: Double) {
        self.source = source
        self.silenceTimeout = silenceTimeout
        self.silenceStart = nil

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.check()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        silenceStart = nil
        source = nil
    }

    private func check() {
        guard let source else { return }

        // Check last 0.5s of audio (8000 samples at 16kHz)
        let samples = source.recentSamples(last: 8000)
        guard samples.count >= 1600 else { return } // need at least 100ms

        let activity = vad.voiceActivity(in: samples)
        let hasVoice = activity.contains(true)

        if hasVoice {
            silenceStart = nil
        } else {
            if silenceStart == nil {
                silenceStart = Date()
            }
            if let start = silenceStart, Date().timeIntervalSince(start) >= silenceTimeout {
                stop()
                onSilenceDetected?()
            }
        }
    }
}
