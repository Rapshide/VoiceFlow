import Foundation
import WhisperKit

actor TranscriptionEngine {
    private var whisperKit: WhisperKit?
    private(set) var isLoaded = false
    private(set) var loadedModelName = ""

    // Base directory: WhisperKit downloads to downloadBase/argmaxinc/whisperkit-coreml/<model>/
    private static var downloadBase: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("VoiceFlow", isDirectory: true)
    }

    private static let cachedModelPathKey = "cachedModelFolderPath"

    // Returns the cached model URL if the folder exists and contains model files.
    // Does NOT touch the network.
    private static func localModelFolder() -> URL? {
        guard let path = UserDefaults.standard.string(forKey: cachedModelPathKey) else { return nil }
        let url = URL(fileURLWithPath: path)
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
        // A valid model folder contains at least one compiled CoreML bundle
        guard contents.contains(where: { $0.hasSuffix(".mlmodelc") }) else { return nil }
        return url
    }

    func loadModel(progressHandler: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        progressHandler(0.01)

        // ── Fast path: model already on disk ─────────────────────────────────
        if let cachedURL = Self.localModelFolder() {
            progressHandler(0.5)
            let kit = try await WhisperKit(
                modelFolder: cachedURL.path,
                verbose: false,
                prewarm: false,
                load: true,
                download: false
            )
            progressHandler(1.0)
            whisperKit = kit
            loadedModelName = cachedURL.lastPathComponent
            isLoaded = true
            return
        }

        // ── Slow path: first launch, download the model ───────────────────────
        let base = Self.downloadBase
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        // Ask WhisperKit which model is best for this device (needs network once)
        let modelSupport = await WhisperKit.recommendedRemoteModels(downloadBase: base)
        let variant = modelSupport.supported.first(where: { $0.contains("turbo") })
                   ?? modelSupport.default

        progressHandler(0.05)

        let modelFolderURL = try await WhisperKit.download(
            variant: variant,
            downloadBase: base,
            progressCallback: { progress in
                let fraction = 0.05 + progress.fractionCompleted * 0.80
                progressHandler(fraction)
            }
        )

        progressHandler(0.90)

        let kit = try await WhisperKit(
            modelFolder: modelFolderURL.path,
            verbose: false,
            prewarm: false,
            load: true,
            download: false
        )

        progressHandler(1.0)

        // Save path so future launches skip the download entirely
        UserDefaults.standard.set(modelFolderURL.path, forKey: Self.cachedModelPathKey)

        whisperKit = kit
        loadedModelName = variant
        isLoaded = true
    }

    func transcribe(audio: [Float], language: String) async throws -> DictationResult {
        guard let kit = whisperKit else {
            throw TranscriptionError.modelNotLoaded
        }

        let startTime = Date()

        let options = DecodingOptions(
            task: .transcribe,
            language: language,
            wordTimestamps: true
        )

        let results = try await kit.transcribe(audioArray: audio, decodeOptions: options) as [TranscriptionResult]

        let duration = Date().timeIntervalSince(startTime)

        guard let first = results.first else {
            return DictationResult(text: "", words: [], duration: duration)
        }

        let rawText: String = first.text
        let fullText = rawText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

        var words: [DictationWord] = []
        for segment in first.segments {
            for w in segment.words ?? [] {
                let rawWord: String = w.word
                let cleaned = rawWord.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                guard !cleaned.isEmpty else { continue }
                words.append(DictationWord(word: cleaned, start: w.start, end: w.end))
            }
        }

        return DictationResult(text: fullText, words: words, duration: duration)
    }
}

enum TranscriptionError: Error {
    case modelNotLoaded
}
