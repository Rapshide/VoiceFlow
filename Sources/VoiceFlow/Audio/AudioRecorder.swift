import AVFoundation

@MainActor
final class AudioRecorder: AudioSourceProtocol {
    private let engine = AVAudioEngine()
    private var buffer: [Float] = []
    private var converter: AVAudioConverter?
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16000,
        channels: 1,
        interleaved: false
    )!

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func start() async throws {
        buffer.removeAll()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)

        guard let conv = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioError.converterCreationFailed
        }
        converter = conv

        let targetFormat = self.targetFormat
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] pcmBuffer, _ in
            guard let self, let conv = self.converter else { return }
            let frameCapacity = AVAudioFrameCount(
                Double(pcmBuffer.frameLength) * targetFormat.sampleRate / inputFormat.sampleRate
            )
            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
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
                    self?.buffer.append(contentsOf: samples)
                }
            }
        }

        engine.prepare()
        try engine.start()
    }

    func stop() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        converter = nil
        let result = buffer
        buffer.removeAll()
        return result
    }

    func recentSamples(last n: Int) -> [Float] {
        if buffer.count <= n { return buffer }
        return Array(buffer.suffix(n))
    }
}

enum AudioError: Error {
    case converterCreationFailed
    case permissionDenied
}
