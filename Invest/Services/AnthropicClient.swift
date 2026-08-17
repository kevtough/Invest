import Foundation

enum AnthropicError: LocalizedError {
    case missingCredentials
    case http(Int, String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "Anthropic API key is not set. Add it in Settings."
        case .http(let code, let body):
            return "Claude request failed (\(code)): \(body)"
        case .emptyResponse:
            return "Claude returned an empty response."
        }
    }
}

/// Minimal client for the Anthropic Messages API.
final class AnthropicClient {
    private let settings: SettingsStore
    private let session: URLSession
    private let apiURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private let apiVersion = "2023-06-01"

    init(settings: SettingsStore, session: URLSession = .shared) {
        self.settings = settings
        self.session = session
    }

    struct TurnMessage {
        let role: String // "user" or "assistant"
        let content: String
    }

    /// Sends a conversation to Claude and returns the assistant's reply text.
    func send(system: String, messages: [TurnMessage], maxTokens: Int = 1024) async throws -> String {
        guard settings.hasAnthropicCredentials else { throw AnthropicError.missingCredentials }

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue(settings.anthropicAPIKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": settings.claudeModel,
            "max_tokens": maxTokens,
            "system": system,
            "messages": messages.map { ["role": $0.role, "content": $0.content] }
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AnthropicError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        struct ContentBlock: Decodable { let type: String; let text: String? }
        struct MessagesResponse: Decodable { let content: [ContentBlock] }

        let decoded = try JSONDecoder().decode(MessagesResponse.self, from: data)
        let text = decoded.content.compactMap { $0.text }.joined()
        guard !text.isEmpty else { throw AnthropicError.emptyResponse }
        return text
    }
}
