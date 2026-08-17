import XCTest
@testable import Invest

final class TradingAgentGuardrailTests: XCTestCase {
    private func makeAgent(risk: RiskSettings = .default, watchlist: [String] = ["AAPL", "TSLA"]) -> TradingAgent {
        let settings = SettingsStore()
        settings.riskSettings = risk
        settings.watchlist = watchlist
        let alpaca = AlpacaClient(settings: settings)
        let claude = AnthropicClient(settings: settings)
        return TradingAgent(alpaca: alpaca, claude: claude, settings: settings)
    }

    private func makeAccount(portfolioValue: Double = 10_000) -> AlpacaAccount {
        AlpacaAccount(
            id: "test",
            status: "ACTIVE",
            currency: "USD",
            cash: "5000",
            portfolioValue: String(portfolioValue),
            buyingPower: "10000",
            equity: String(portfolioValue),
            lastEquity: String(portfolioValue),
            daytradeCount: 0,
            patternDayTrader: false
        )
    }

    private func makePosition(symbol: String, marketValue: Double) -> AlpacaPosition {
        AlpacaPosition(
            symbol: symbol,
            qty: "10",
            side: "long",
            avgEntryPrice: "100",
            currentPrice: "110",
            marketValue: String(marketValue),
            unrealizedPl: "100",
            unrealizedPlpc: "0.1",
            costBasis: "1000"
        )
    }

    func testApprovesReasonableBuyOnWatchlistSymbol() {
        let agent = makeAgent()
        let proposal = TradeProposal(symbol: "AAPL", action: .buy, notionalUSD: 200, confidence: 0.8, reasoning: "test")
        let result = agent.applyGuardrails(proposal, account: makeAccount(), positions: [])
        XCTAssertEqual(result.status, .approved)
    }

    func testBlocksLowConfidence() {
        let agent = makeAgent()
        let proposal = TradeProposal(symbol: "AAPL", action: .buy, notionalUSD: 200, confidence: 0.2, reasoning: "test")
        let result = agent.applyGuardrails(proposal, account: makeAccount(), positions: [])
        XCTAssertEqual(result.status, .blocked)
        XCTAssertNotNil(result.blockReason)
    }

    func testBlocksSymbolNotOnWatchlistOrHeld() {
        let agent = makeAgent(watchlist: ["AAPL"])
        let proposal = TradeProposal(symbol: "GME", action: .buy, notionalUSD: 200, confidence: 0.9, reasoning: "test")
        let result = agent.applyGuardrails(proposal, account: makeAccount(), positions: [])
        XCTAssertEqual(result.status, .blocked)
    }

    func testAllowsHeldSymbolEvenIfNotOnWatchlist() {
        let agent = makeAgent(watchlist: ["AAPL"])
        let proposal = TradeProposal(symbol: "GME", action: .sell, notionalUSD: 100, confidence: 0.9, reasoning: "test")
        let result = agent.applyGuardrails(proposal, account: makeAccount(), positions: [makePosition(symbol: "GME", marketValue: 500)])
        XCTAssertEqual(result.status, .approved)
    }

    func testBlocksOrderAboveMaxNotional() {
        var risk = RiskSettings.default
        risk.maxOrderNotionalUSD = 100
        let agent = makeAgent(risk: risk)
        let proposal = TradeProposal(symbol: "AAPL", action: .buy, notionalUSD: 500, confidence: 0.9, reasoning: "test")
        let result = agent.applyGuardrails(proposal, account: makeAccount(), positions: [])
        XCTAssertEqual(result.status, .blocked)
    }

    func testBlocksOrderAbovePortfolioPercentCap() {
        var risk = RiskSettings.default
        risk.maxPositionPercentOfPortfolio = 0.05 // 5% of portfolio
        risk.maxOrderNotionalUSD = 100_000 // not the limiting factor
        let agent = makeAgent(risk: risk)
        // 5% of a $10,000 portfolio is $500; propose $600.
        let proposal = TradeProposal(symbol: "AAPL", action: .buy, notionalUSD: 600, confidence: 0.9, reasoning: "test")
        let result = agent.applyGuardrails(proposal, account: makeAccount(portfolioValue: 10_000), positions: [])
        XCTAssertEqual(result.status, .blocked)
    }

    func testBlocksSellWithNoExistingPosition() {
        let agent = makeAgent()
        let proposal = TradeProposal(symbol: "AAPL", action: .sell, notionalUSD: 100, confidence: 0.9, reasoning: "test")
        let result = agent.applyGuardrails(proposal, account: makeAccount(), positions: [])
        XCTAssertEqual(result.status, .blocked)
    }

    func testAllowedSymbolsListRestrictsEvenWatchlistSymbols() {
        var risk = RiskSettings.default
        risk.allowedSymbols = ["MSFT"]
        let agent = makeAgent(risk: risk, watchlist: ["AAPL", "MSFT"])
        let proposal = TradeProposal(symbol: "AAPL", action: .buy, notionalUSD: 100, confidence: 0.9, reasoning: "test")
        let result = agent.applyGuardrails(proposal, account: makeAccount(), positions: [])
        XCTAssertEqual(result.status, .blocked)
    }

    func testMissingNotionalIsBlocked() {
        let agent = makeAgent()
        let proposal = TradeProposal(symbol: "AAPL", action: .buy, notionalUSD: nil, confidence: 0.9, reasoning: "test")
        let result = agent.applyGuardrails(proposal, account: makeAccount(), positions: [])
        XCTAssertEqual(result.status, .blocked)
    }
}
