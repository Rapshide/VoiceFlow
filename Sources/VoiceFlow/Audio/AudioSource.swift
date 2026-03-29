import Foundation

enum RecordingMode: Int, CaseIterable {
    case pushToTalk = 0
    case vadToggle = 1

    var displayName: String {
        switch self {
        case .pushToTalk: return "Push-to-Talk"
        case .vadToggle: return "VAD Toggle"
        }
    }
}

enum AudioSourceSelection: Int, CaseIterable {
    case microphone = 0
    case systemAudio = 1

    var displayName: String {
        switch self {
        case .microphone: return "Microphone"
        case .systemAudio: return "System Audio"
        }
    }
}

@MainActor
protocol AudioSourceProtocol: AnyObject {
    func requestPermission() async -> Bool
    func start() throws
    func stop() -> [Float]
    func recentSamples(last n: Int) -> [Float]
}
