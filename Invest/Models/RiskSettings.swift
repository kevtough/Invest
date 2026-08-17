import Foundation

/// Guardrails enforced in Swift code, independent of whatever the AI proposes.
/// These are the last line of defense before any real order is submitted.
struct RiskSettings: Codable, Equatable {
    /// Max size of any single order as a fraction of current portfolio value.
    var maxPositionPercentOfPortfolio: Double = 0.10
    /// Hard dollar cap per order, regardless of portfolio size.
    var maxOrderNotionalUSD: Double = 500
    /// Max number of agent-initiated orders allowed in a single calendar day.
    var maxTradesPerDay: Int = 5
    /// Proposals below this confidence are never eligible to auto-execute.
    var minConfidenceToExecute: Double = 0.65
    /// If non-empty, the agent may only trade these symbols. Empty = watchlist symbols only.
    var allowedSymbols: [String] = []
    /// If true, eligible proposals execute automatically. If false, they always
    /// wait for a manual approval tap in the Agent tab.
    var autoExecuteEnabled: Bool = false

    static let `default` = RiskSettings()
}
