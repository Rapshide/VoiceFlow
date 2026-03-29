import Foundation

struct DictationWord: Sendable, Codable {
    let word: String
    let start: Float
    let end: Float
}

struct DictationResult: Sendable, Codable {
    let text: String
    let words: [DictationWord]
    let duration: TimeInterval
}
