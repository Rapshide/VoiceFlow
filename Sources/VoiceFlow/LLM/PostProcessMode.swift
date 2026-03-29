import Foundation

enum PostProcessMode: String, CaseIterable, Codable {
    case none = "None"
    case cleanup = "Clean up"
    case formal = "Formal"
    case summary = "Summary"
    case custom = "Custom"

    var systemPrompt: String {
        switch self {
        case .none:
            return ""
        case .cleanup:
            return "You are a text editor. Fix grammar, punctuation, and obvious speech-to-text errors in the following transcription. Keep the original meaning and tone. Output only the corrected text, nothing else."
        case .formal:
            return "You are a text editor. Rewrite the following transcription in a formal, professional tone. Fix any grammar or punctuation errors. Output only the rewritten text, nothing else."
        case .summary:
            return "Summarize the following transcription concisely. Keep the key points. Output only the summary, nothing else."
        case .custom:
            return "" // User-provided prompt is used instead
        }
    }
}
