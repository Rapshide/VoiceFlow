import Foundation
import Observation
import AppKit

enum RecordingState {
    case idle
    case recording
    case transcribing
    case postProcessing
    case showingResult(DictationResult)
    case error(String)
}

@Observable
@MainActor
final class AppStateManager {
    static let shared = AppStateManager()

    var state: RecordingState = .idle
    var language: String = UserDefaults.standard.string(forKey: "language") ?? "hu"
    var frontmostAppPID: pid_t = 0
    var modelDownloadProgress: Double = 0.0
    var isModelLoaded: Bool = false
    var loadedModelName: String = ""

    var recordingMode: RecordingMode {
        get {
            let raw = UserDefaults.standard.integer(forKey: "recordingMode")
            return RecordingMode(rawValue: raw) ?? .pushToTalk
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "recordingMode")
        }
    }

    var silenceTimeout: Double {
        get {
            let val = UserDefaults.standard.double(forKey: "silenceTimeout")
            return val > 0 ? val : 1.5
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "silenceTimeout")
        }
    }

    var audioSource: AudioSourceSelection {
        get {
            let raw = UserDefaults.standard.integer(forKey: "audioSource")
            return AudioSourceSelection(rawValue: raw) ?? .microphone
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "audioSource")
        }
    }

    // MARK: - LLM Post-processing

    var postProcessMode: PostProcessMode {
        get {
            let raw = UserDefaults.standard.string(forKey: "postProcessMode") ?? PostProcessMode.none.rawValue
            return PostProcessMode(rawValue: raw) ?? .none
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "postProcessMode")
        }
    }

    var ollamaModel: String {
        get { UserDefaults.standard.string(forKey: "ollamaModel") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "ollamaModel") }
    }

    var customLLMPrompt: String {
        get { UserDefaults.standard.string(forKey: "customLLMPrompt") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "customLLMPrompt") }
    }

    var isOllamaAvailable: Bool = false
    var ollamaModels: [String] = []

    // MARK: - Hotword

    var hotwordEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "hotwordEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "hotwordEnabled") }
    }

    var hotword: String {
        get { UserDefaults.standard.string(forKey: "hotword") ?? "Voice" }
        set { UserDefaults.standard.set(newValue, forKey: "hotword") }
    }

    // MARK: - Hotkey

    var hotkeyOption: HotkeyOption {
        get {
            let raw = UserDefaults.standard.integer(forKey: "hotkeyCode")
            return HotkeyOption(rawValue: raw) ?? .rightOption
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "hotkeyCode")
        }
    }

    private init() {}

    func trackFrontmostApp() {
        if let app = NSWorkspace.shared.frontmostApplication {
            frontmostAppPID = app.processIdentifier
        }
    }

    func setLanguage(_ lang: String) {
        language = lang
        UserDefaults.standard.set(lang, forKey: "language")
    }

    /// Clears the cached model path so the next load triggers a fresh download.
    func clearModelCache() {
        UserDefaults.standard.removeObject(forKey: "cachedModelFolderPath")
        isModelLoaded = false
        loadedModelName = ""
        modelDownloadProgress = 0.0
    }
}
