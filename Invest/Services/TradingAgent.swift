import Foundation
import Observation

/// The AI trading agent. Asks Claude for trade ideas based on current account
/// state, then runs every idea through hard-coded risk guardrails before it is
/// ever eligible to execute. Execution itself only happens either when the user
/// taps "Approve" on a proposal, or automatically if `RiskSettings.autoExecuteEnabled`
/// is on — which is off by default.
///
/// Safety model (defense in depth):
/// 1. Claude never calls a tool that places orders; it only returns a JSON opinion.
/// 2. `applyGuardrails` evaluates every proposal against confidence, symbol allow-list,
///    per-order and per-portfolio dollar caps, and a daily trade cap.
/// 3. `execute` re-checks the daily cap immediately before submitting the order.
@Observable
final class TradingAgent {
    private let alpaca: AlpacaClient
    private let claude: AnthropicClient
    private let settings: SettingsStore

    var proposals: [TradeProposal] = []
    var isRunning = false
    var lastError: String?
    var lastRunSummary: String?
    var lastRunDate: Date?

    init(alpaca: AlpacaClient, claude: AnthropicClient, settings: SettingsStore) {
        self.alpaca = alpaca
        self.claude = claude
        self.settings = settings
    }

    func runAnalysis() async {
        isRunning = true
        lastError = nil
        defer { isRunning = false }

        do {
            let account = try await alpaca.fetchAccount()
            let positions = try await alpaca.fetchPositions()
            let symbols = Array(Set(settings.watchlist + positions.map { $0.symbol })).sorted()
            let quotes = await alpaca.fetchLatestQuotes(symbols: symbols)

            let prompt = Self.buildPrompt(account: account, positions: positions, quotes: quotes, watchlist: settings.watchlist)
            let raw = try await claude.send(
                system: Self.systemPrompt,
                messages: [.init(role: "user", content: prompt)],
                maxTokens: 2048
            )
            let parsed = try Self.parse(raw)

            var newProposals = parsed.proposals
                .map { raw -> TradeProposal in
                    TradeProposal(
                        symbol: raw.symbol,
                        action: TradeAction(rawValue: raw.action.lowercased()) ?? .hold,
                        notionalUSD: raw.notionalUSD,
                        confidence: raw.confidence,
                        reasoning: raw.reasoning
                    )
                }
                .filter { $0.action != .hold }

            newProposals = newProposals.map { applyGuardrails($0, account: account, positions: positions) }

            proposals = newProposals + proposals
            lastRunSummary = parsed.summary
            lastRunDate = Date()

            if settings.riskSettings.autoExecuteEnabled {
                for proposal in newProposals where proposal.status == .approved {
                    await execute(proposal)
                }
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Manual approval path used from the Agent tab when auto-execute is off.
    func approve(_ id: UUID) async {
        guard let proposal = proposals.first(where: { $0.id == id }), proposal.status == .approved else { return }
        await execute(proposal)
    }

    func reject(_ id: UUID) {
        guard let index = proposals.firstIndex(where: { $0.id == id }) else { return }
        proposals[index].status = .rejected
    }

    // MARK: - Guardrails

    func applyGuardrails(_ input: TradeProposal, account: AlpacaAccount, positions: [AlpacaPosition]) -> TradeProposal {
        var proposal = input
        let risk = settings.riskSettings

        func blocked(_ reason: String) -> TradeProposal {
            proposal.status = .blocked
            proposal.blockReason = reason
            return proposal
        }

        guard let notional = proposal.notionalUSD, notional > 0 else {
            return blocked("Missing or invalid order size.")
        }

        if proposal.confidence < risk.minConfidenceToExecute {
            return blocked("Confidence \(Int(proposal.confidence * 100))% is below your minimum of \(Int(risk.minConfidenceToExecute * 100))%.")
        }

        if !risk.allowedSymbols.isEmpty {
            if !risk.allowedSymbols.contains(proposal.symbol) {
                return blocked("\(proposal.symbol) is not in your allowed symbols list.")
            }
        } else if !settings.watchlist.contains(proposal.symbol) && !positions.contains(where: { $0.symbol == proposal.symbol }) {
            return blocked("\(proposal.symbol) is not on your watchlist or in your positions.")
        }

        if notional > risk.maxOrderNotionalUSD {
            return blocked("$\(Int(notional)) exceeds your max order size of $\(Int(risk.maxOrderNotionalUSD)).")
        }

        let maxByPortfolioPercent = account.portfolioValueDouble * risk.maxPositionPercentOfPortfolio
        if notional > maxByPortfolioPercent {
            return blocked("$\(Int(notional)) exceeds \(Int(risk.maxPositionPercentOfPortfolio * 100))% of your portfolio ($\(Int(maxByPortfolioPercent))).")
        }

        if proposal.action == .sell {
            let held = positions.first(where: { $0.symbol == proposal.symbol })?.marketValueDouble ?? 0
            if held <= 0 {
                return blocked("No existing position in \(proposal.symbol) to sell.")
            }
        }

        if tradesExecutedToday() >= risk.maxTradesPerDay {
            return blocked("Daily trade limit of \(risk.maxTradesPerDay) already reached.")
        }

        proposal.status = .approved
        return proposal
    }

    private func execute(_ proposal: TradeProposal) async {
        guard let index = proposals.firstIndex(where: { $0.id == proposal.id }) else { return }
        guard proposal.status == .approved, let notional = proposal.notionalUSD else { return }

        guard tradesExecutedToday() < settings.riskSettings.maxTradesPerDay else {
            proposals[index].status = .blocked
            proposals[index].blockReason = "Daily trade limit reached before execution."
            return
        }

        do {
            _ = try await alpaca.placeOrder(symbol: proposal.symbol, side: proposal.action, notionalUSD: notional)
            proposals[index].status = .executed
            recordTradeExecuted()
        } catch {
            proposals[index].status = .failed
            proposals[index].blockReason = error.localizedDescription
        }
    }

    // MARK: - Daily trade counter (resets automatically at midnight, per calendar day key)

    private func todayKey() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "agent.tradesExecuted." + formatter.string(from: Date())
    }

    private func tradesExecutedToday() -> Int {
        UserDefaults.standard.integer(forKey: todayKey())
    }

    private func recordTradeExecuted() {
        let key = todayKey()
        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: key) + 1, forKey: key)
    }

    // MARK: - Prompting

    static let systemPrompt = """
    You are an investment research assistant embedded in a personal iOS app. \
    You analyze a user's portfolio and watchlist and propose trades. You do NOT \
    place trades yourself - the app applies its own risk rules and either asks \
    for manual approval or executes automatically, depending on the user's settings. \
    Be conservative: prefer to propose nothing unless you have a clear, well-reasoned \
    idea, and never propose more than a few trades at once. Always reply with ONLY a \
    single JSON object, no markdown fences, no prose outside the JSON, matching exactly \
    this shape:
    {"summary": "one or two sentence overview", "proposals": [{"symbol": "AAPL", "action": "buy", "notionalUSD": 100.0, "confidence": 0.7, "reasoning": "short explanation"}]}
    "action" must be "buy" or "sell". Omit a symbol entirely instead of proposing to hold it. \
    "confidence" is your own calibrated 0.0-1.0 estimate of how strong the idea is. \
    "notionalUSD" is the dollar amount to trade, not a share count.
    """

    static func buildPrompt(account: AlpacaAccount, positions: [AlpacaPosition], quotes: [String: LatestQuote], watchlist: [String]) -> String {
        var lines: [String] = []
        lines.append("Account: equity=$\(String(format: "%.2f", account.equityValue)), cash=$\(String(format: "%.2f", account.cashValue)), buying_power=$\(String(format: "%.2f", account.buyingPowerValue))")
        lines.append("")
        lines.append("Current positions:")
        if positions.isEmpty {
            lines.append("(none)")
        } else {
            for position in positions {
                lines.append("- \(position.symbol): qty=\(position.qty), avg_entry=\(position.avgEntryPrice), current=\(position.currentPrice ?? "?"), unrealized_pl=\(position.unrealizedPl ?? "0") (\(String(format: "%.1f", position.unrealizedPLPercent * 100))%)")
            }
        }
        lines.append("")
        lines.append("Watchlist quotes:")
        for symbol in watchlist {
            if let quote = quotes[symbol] {
                lines.append("- \(symbol): bid=\(quote.bidPrice), ask=\(quote.askPrice)")
            } else {
                lines.append("- \(symbol): quote unavailable")
            }
        }
        return lines.joined(separator: "\n")
    }

    static func parse(_ raw: String) throws -> RawAgentResponse {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text.replacingOccurrences(of: "```json", with: "")
            text = text.replacingOccurrences(of: "```", with: "")
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let data = text.data(using: .utf8) else { throw AnthropicError.emptyResponse }
        return try JSONDecoder().decode(RawAgentResponse.self, from: data)
    }
}
