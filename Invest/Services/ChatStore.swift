import Foundation
import Observation

/// Drives the free-form research chat with Claude. Optionally includes a
/// snapshot of the user's portfolio/watchlist as context for the question.
@Observable
final class ChatStore {
    private let claude: AnthropicClient
    private let alpaca: AlpacaClient
    private let settings: SettingsStore

    var messages: [ChatMessage] = []
    var isSending = false
    var lastError: String?
    var includePortfolioContext = true

    private static let systemPrompt = """
    You are a knowledgeable investment research assistant inside a personal iOS app. \
    Answer clearly and concisely. When asked for opinions on trades, be explicit about \
    uncertainty and risk. You are not placing any trades in this conversation - this is \
    research and discussion only. If portfolio context is included below, use it, but do \
    not assume the user wants to act on it unless asked.
    """

    init(claude: AnthropicClient, alpaca: AlpacaClient, settings: SettingsStore) {
        self.claude = claude
        self.alpaca = alpaca
        self.settings = settings
    }

    func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        messages.append(ChatMessage(role: .user, text: trimmed))
        isSending = true
        lastError = nil
        defer { isSending = false }

        do {
            var contextPrefix = ""
            if includePortfolioContext {
                contextPrefix = await portfolioContext() + "\n\n"
            }

            let turns = messages.map {
                AnthropicClient.TurnMessage(role: $0.role.rawValue, content: $0.text)
            }
            var finalTurns = turns
            if !contextPrefix.isEmpty, let last = finalTurns.last {
                finalTurns[finalTurns.count - 1] = .init(role: last.role, content: contextPrefix + last.content)
            }

            let reply = try await claude.send(system: Self.systemPrompt, messages: finalTurns, maxTokens: 1536)
            messages.append(ChatMessage(role: .assistant, text: reply))
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func portfolioContext() async -> String {
        guard settings.hasAlpacaCredentials else { return "(No brokerage account connected.)" }
        do {
            let account = try await alpaca.fetchAccount()
            let positions = try await alpaca.fetchPositions()
            var lines = ["Current portfolio context:"]
            lines.append("Equity: $\(String(format: "%.2f", account.equityValue)), Cash: $\(String(format: "%.2f", account.cashValue))")
            if positions.isEmpty {
                lines.append("No open positions.")
            } else {
                for position in positions {
                    lines.append("\(position.symbol): \(position.qty) shares @ avg $\(position.avgEntryPrice)")
                }
            }
            lines.append("Watchlist: \(settings.watchlist.joined(separator: ", "))")
            return lines.joined(separator: "\n")
        } catch {
            return "(Portfolio context unavailable: \(error.localizedDescription))"
        }
    }
}
