import Foundation
import Observation
import AppKit

enum RecordingState {
    case idle
    case recording
    case transcribing
    case postProcessing
    case showingResult   // text already pasted; panel shows a brief "✓ Done" pill
    case error(String)
}

@Observable
@MainActor
final class AppStateManager {
    static let shared = AppStateManager()

    // MARK: - Transient state (not persisted)

    var state: RecordingState = .idle
    var frontmostAppPID: pid_t = 0
    var modelDownloadProgress: Double = 0.0
    var isModelLoaded: Bool = false
    var loadedModelName: String = ""
    var isOllamaAvailable: Bool = false
    var ollamaModels: [String] = []
    /// Set briefly when the user toggles the audio source via hotkey — cleared after ~2 s.
    var sourceNotification: String? = nil

    // MARK: - Persisted settings (stored properties so @Observable tracks them for UI updates)

    var language: String = UserDefaults.standard.string(forKey: "language") ?? "hu" {
        didSet { UserDefaults.standard.set(language, forKey: "language") }
    }

    var recordingMode: RecordingMode = {
        let raw = UserDefaults.standard.integer(forKey: "recordingMode")
        return RecordingMode(rawValue: raw) ?? .pushToTalk
    }() {
        didSet { UserDefaults.standard.set(recordingMode.rawValue, forKey: "recordingMode") }
    }

    var silenceTimeout: Double = {
        let v = UserDefaults.standard.double(forKey: "silenceTimeout")
        return v > 0 ? v : 1.5
    }() {
        didSet { UserDefaults.standard.set(silenceTimeout, forKey: "silenceTimeout") }
    }

    var audioSource: AudioSourceSelection = {
        let raw = UserDefaults.standard.integer(forKey: "audioSource")
        return AudioSourceSelection(rawValue: raw) ?? .microphone
    }() {
        didSet { UserDefaults.standard.set(audioSource.rawValue, forKey: "audioSource") }
    }

    var postProcessMode: PostProcessMode = {
        let raw = UserDefaults.standard.string(forKey: "postProcessMode") ?? PostProcessMode.none.rawValue
        return PostProcessMode(rawValue: raw) ?? .none
    }() {
        didSet { UserDefaults.standard.set(postProcessMode.rawValue, forKey: "postProcessMode") }
    }

    var ollamaModel: String = UserDefaults.standard.string(forKey: "ollamaModel") ?? "" {
        didSet { UserDefaults.standard.set(ollamaModel, forKey: "ollamaModel") }
    }

    var customLLMPrompt: String = UserDefaults.standard.string(forKey: "customLLMPrompt") ?? "" {
        didSet { UserDefaults.standard.set(customLLMPrompt, forKey: "customLLMPrompt") }
    }

    var hotwordEnabled: Bool = UserDefaults.standard.bool(forKey: "hotwordEnabled") {
        didSet { UserDefaults.standard.set(hotwordEnabled, forKey: "hotwordEnabled") }
    }

    var hotword: String = UserDefaults.standard.string(forKey: "hotword") ?? "Voice" {
        didSet { UserDefaults.standard.set(hotword, forKey: "hotword") }
    }

    var recordingHotkey: HotkeyConfig = {
        if let data = UserDefaults.standard.data(forKey: "recordingHotkey"),
           let config = try? JSONDecoder().decode(HotkeyConfig.self, from: data) {
            return config
        }
        let legacy = UserDefaults.standard.integer(forKey: "hotkeyCode")
        return legacy != 0 ? HotkeyConfig.fromLegacyCode(legacy) : .defaultRecording
    }() {
        didSet {
            if let data = try? JSONEncoder().encode(recordingHotkey) {
                UserDefaults.standard.set(data, forKey: "recordingHotkey")
            }
        }
    }

    var sourceToggleHotkey: HotkeyConfig = {
        if let data = UserDefaults.standard.data(forKey: "sourceToggleHotkey"),
           let config = try? JSONDecoder().decode(HotkeyConfig.self, from: data) {
            return config
        }
        return .defaultSourceToggle
    }() {
        didSet {
            if let data = try? JSONEncoder().encode(sourceToggleHotkey) {
                UserDefaults.standard.set(data, forKey: "sourceToggleHotkey")
            }
        }
    }

    // MARK: -

    private init() {}

    func trackFrontmostApp() {
        if let app = NSWorkspace.shared.frontmostApplication {
            frontmostAppPID = app.processIdentifier
        }
    }

    func setLanguage(_ lang: String) {
        language = lang
    }

    func clearModelCache() {
        UserDefaults.standard.removeObject(forKey: "cachedModelFolderPath")
        isModelLoaded = false
        loadedModelName = ""
        modelDownloadProgress = 0.0
    }
}
