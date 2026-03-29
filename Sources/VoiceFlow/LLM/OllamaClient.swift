import Foundation

actor OllamaClient {
    private let baseURL = URL(string: "http://localhost:11434")!
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }

    // MARK: - Availability

    func isAvailable() async -> Bool {
        let url = baseURL.appendingPathComponent("api/tags")
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        do {
            let (_, response) = try await session.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - List models

    struct TagsResponse: Decodable {
        struct Model: Decodable {
            let name: String
        }
        let models: [Model]?
    }

    func availableModels() async -> [String] {
        let url = baseURL.appendingPathComponent("api/tags")
        do {
            let (data, _) = try await session.data(from: url)
            let response = try JSONDecoder().decode(TagsResponse.self, from: data)
            return response.models?.map(\.name) ?? []
        } catch {
            return []
        }
    }

    // MARK: - Generate

    func process(text: String, mode: PostProcessMode, customPrompt: String = "", model: String) async throws -> String {
        let systemPrompt = mode == .custom ? customPrompt : mode.systemPrompt
        guard !systemPrompt.isEmpty else { return text }

        let url = baseURL.appendingPathComponent("api/generate")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "system": systemPrompt,
            "prompt": text,
            "stream": false
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw OllamaError.requestFailed
        }

        struct GenerateResponse: Decodable {
            let response: String
        }
        let result = try JSONDecoder().decode(GenerateResponse.self, from: data)
        let trimmed = result.response.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? text : trimmed
    }
}

enum OllamaError: Error {
    case requestFailed
    case noResponse
}
