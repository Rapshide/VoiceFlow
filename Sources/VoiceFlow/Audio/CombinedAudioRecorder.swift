import Foundation

/// Records microphone and system audio simultaneously and mixes them into a single
/// Float32 16 kHz buffer — ideal for meeting transcription where both the local
/// speaker (mic) and remote participants (system audio) need to be captured.
@MainActor
final class CombinedAudioRecorder: AudioSourceProtocol {
    private let mic    = AudioRecorder()
    private let system = SystemAudioRecorder()

    func requestPermission() async -> Bool {
        // Both permissions can be requested sequentially; each returns immediately if already decided.
        let micOK = await mic.requestPermission()
        let sysOK = await system.requestPermission()
        return micOK && sysOK
    }

    func start() async throws {
        // Start mic first (synchronous under the hood), then await system audio setup.
        try await mic.start()
        try await system.start()
    }

    func stop() -> [Float] {
        let micSamples = mic.stop()
        let sysSamples = system.stop()
        return mix(micSamples, sysSamples)
    }

    func recentSamples(last n: Int) -> [Float] {
        let micSamples = mic.recentSamples(last: n)
        let sysSamples = system.recentSamples(last: n)
        return mix(micSamples, sysSamples)
    }

    // MARK: - Mixing

    private func mix(_ a: [Float], _ b: [Float]) -> [Float] {
        let count = max(a.count, b.count)
        return (0..<count).map { i in
            let sa = i < a.count ? a[i] : 0
            let sb = i < b.count ? b[i] : 0
            return max(-1.0, min(1.0, sa + sb))
        }
    }
}
