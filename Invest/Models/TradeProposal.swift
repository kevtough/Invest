import Foundation

enum TradeAction: String, Codable {
    case buy
    case sell
    case hold
}

enum ProposalStatus: String, Codable {
    case pending
    case approved
    case rejected
    case executed
    case failed
    case blocked // rejected automatically by a risk guardrail
}

/// A single trade suggested by the AI trading agent for one symbol.
/// Nothing here executes on its own — `TradingAgent` decides whether it is
/// eligible to run, and either waits for manual approval or auto-executes it,
/// depending on user settings.
struct TradeProposal: Identifiable, Codable, Equatable {
    let id: UUID
    let symbol: String
    let action: TradeAction
    /// Dollar amount to trade. Preferred over share quantity for fractional support.
    let notionalUSD: Double?
    let confidence: Double // 0.0...1.0, as reported by the model
    let reasoning: String
    let createdAt: Date
    var status: ProposalStatus
    /// Filled in if a guardrail blocked this proposal from being eligible to execute.
    var blockReason: String?

    init(
        id: UUID = UUID(),
        symbol: String,
        action: TradeAction,
        notionalUSD: Double?,
        confidence: Double,
        reasoning: String,
        createdAt: Date = Date(),
        status: ProposalStatus = .pending,
        blockReason: String? = nil
    ) {
        self.id = id
        self.symbol = symbol.uppercased()
        self.action = action
        self.notionalUSD = notionalUSD
        self.confidence = confidence
        self.reasoning = reasoning
        self.createdAt = createdAt
        self.status = status
        self.blockReason = blockReason
    }
}

/// The raw shape the model is asked to reply with (before guardrails/UUIDs are applied).
struct RawTradeProposal: Codable {
    let symbol: String
    let action: String
    let notionalUSD: Double?
    let confidence: Double
    let reasoning: String
}

struct RawAgentResponse: Codable {
    let proposals: [RawTradeProposal]
    let summary: String
}
