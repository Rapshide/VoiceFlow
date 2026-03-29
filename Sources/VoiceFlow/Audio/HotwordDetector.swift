import AVFoundation
import WhisperKit

@MainActor
final class HotwordDetector {
    private var engine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private var rollingBuffer: [Float] = []
    private var checkTimer: Timer?
    private let vad: EnergyVAD
    private let bufferDuration: Int = 3 // seconds
    private let sampleRate: Int = 16000

    private var maxBufferSamples: Int { sampleRate * bufferDuration }

    var hotword: String = "Voice"
    var onHotwordDetected: (() -> Void)?

    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16000,
        channels: 1,
        interleaved: false
    )!

    /// The transcription engine to use for hotword detection.
    /// Set this before calling start().
    weak var transcriptionEngine: TranscriptionEngineRef?

    init() {
        self.vad = EnergyVAD(
            sampleRate: 16000,
            frameLength: 0.1,
            frameOverlap: 0.0,
            energyThreshold: 0.02
        )
    }

    func start() {
        stop()

        let newEngine = AVAudioEngine()
        engine = newEngine

        let inputNode = newEngine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)

        guard let conv = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            print("HotwordDetector: failed to create converter")
            return
        }
        converter = conv

        let targetFmt = self.targetFormat
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] pcmBuffer, _ in
            guard let self, let conv = self.converter else { return }
            let frameCapacity = AVAudioFrameCount(
                Double(pcmBuffer.frameLength) * targetFmt.sampleRate / inputFormat.sampleRate
            )
            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFmt,
                frameCapacity: frameCapacity
            ) else { return }

            var error: NSError?
            var inputConsumed = false
            conv.convert(to: convertedBuffer, error: &error) { _, outStatus in
                if inputConsumed {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                inputConsumed = true
                outStatus.pointee = .haveData
                return pcmBuffer
            }

            if error == nil, let channelData = convertedBuffer.floatChannelData {
                let count = Int(convertedBuffer.frameLength)
                let samples = Array(UnsafeBufferPointer(start: channelData[0], count: count))
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.rollingBuffer.append(contentsOf: samples)
                    // Keep only the last N seconds
                    if self.rollingBuffer.count > self.maxBufferSamples {
                        self.rollingBuffer.removeFirst(self.rollingBuffer.count - self.maxBufferSamples)
                    }
                }
            }
        }

        newEngine.prepare()
        do {
            try newEngine.start()
        } catch {
            print("HotwordDetector: failed to start engine: \(error)")
            return
        }

        // Check for hotword every 1.5 seconds
        checkTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.checkForHotword()
            }
        }
    }

    func stop() {
        checkTimer?.invalidate()
        checkTimer = nil
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
        converter = nil
        rollingBuffer.removeAll()
    }

    private func checkForHotword() async {
        // Need at least 1 second of audio
        guard rollingBuffer.count >= sampleRate else { return }

        // VAD gate: only transcribe if there's voice activity
        let activity = vad.voiceActivity(in: rollingBuffer)
        guard activity.contains(true) else { return }

        // Run a quick transcription on the rolling buffer
        guard let engine = transcriptionEngine else { return }
        do {
            let result = try await engine.transcribe(audio: rollingBuffer, language: "en")
            let text = result.text.lowercased()
            if text.contains(hotword.lowercased()) {
                // Clear buffer to avoid re-triggering
                rollingBuffer.removeAll()
                onHotwordDetected?()
            }
        } catch {
            // Silently ignore transcription errors during hotword detection
        }
    }
}

/// Type-erased reference to TranscriptionEngine so HotwordDetector
/// doesn't need to import it directly as an actor.
typealias TranscriptionEngineRef = TranscriptionEngine
