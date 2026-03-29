import Foundation
import ScreenCaptureKit
import AVFoundation

@MainActor
final class SystemAudioRecorder: NSObject, AudioSourceProtocol {
    private var stream: SCStream?
    private var buffer: [Float] = []
    private var streamOutput: SystemAudioStreamOutput?

    func requestPermission() async -> Bool {
        do {
            // Requesting shareable content implicitly triggers the permission prompt
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            return true
        } catch {
            print("SystemAudioRecorder: permission denied: \(error)")
            return false
        }
    }

    func start() throws {
        buffer.removeAll()

        let output = SystemAudioStreamOutput { [weak self] samples in
            Task { @MainActor [weak self] in
                self?.buffer.append(contentsOf: samples)
            }
        }
        streamOutput = output

        // Start capture asynchronously — the stream setup requires async calls
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                guard let display = content.displays.first else {
                    throw SystemAudioError.noDisplay
                }

                let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
                let config = SCStreamConfiguration()
                config.capturesAudio = true
                config.excludesCurrentProcessAudio = true
                config.sampleRate = 16000
                config.channelCount = 1

                let newStream = SCStream(filter: filter, configuration: config, delegate: nil)
                try newStream.addStreamOutput(output, type: .audio, sampleHandlerQueue: .global())
                try await newStream.startCapture()
                await MainActor.run { self.stream = newStream }
            } catch {
                print("SystemAudioRecorder: failed to start: \(error)")
            }
        }
    }

    func stop() -> [Float] {
        if let stream {
            Task {
                try? await stream.stopCapture()
            }
        }
        stream = nil
        streamOutput = nil
        let result = buffer
        buffer.removeAll()
        return result
    }

    func recentSamples(last n: Int) -> [Float] {
        if buffer.count <= n { return buffer }
        return Array(buffer.suffix(n))
    }
}

enum SystemAudioError: Error {
    case noDisplay
    case permissionDenied
}

// MARK: - Stream output handler

private final class SystemAudioStreamOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    private let onSamples: @Sendable ([Float]) -> Void

    init(onSamples: @escaping @Sendable ([Float]) -> Void) {
        self.onSamples = onSamples
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }

        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
        guard status == kCMBlockBufferNoErr, let dataPointer else { return }

        // Check the audio format — ScreenCaptureKit typically delivers Float32
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
        let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)?.pointee
        guard let asbd, asbd.mFormatID == kAudioFormatLinearPCM else { return }

        let bytesPerSample = Int(asbd.mBitsPerChannel / 8)
        guard bytesPerSample > 0 else { return }
        let sampleCount = length / bytesPerSample

        if asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0 && bytesPerSample == 4 {
            // Already Float32
            let floatPtr = UnsafeRawPointer(dataPointer).bindMemory(to: Float.self, capacity: sampleCount)
            let samples = Array(UnsafeBufferPointer(start: floatPtr, count: sampleCount))
            onSamples(samples)
        } else if asbd.mFormatFlags & kAudioFormatFlagIsSignedInteger != 0 && bytesPerSample == 2 {
            // Int16 → Float32
            let int16Ptr = UnsafeRawPointer(dataPointer).bindMemory(to: Int16.self, capacity: sampleCount)
            let samples = (0..<sampleCount).map { Float(int16Ptr[$0]) / 32768.0 }
            onSamples(samples)
        }
    }
}
