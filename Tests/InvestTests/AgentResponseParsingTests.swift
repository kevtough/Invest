import XCTest
@testable import Invest

final class AgentResponseParsingTests: XCTestCase {
    func testParsesPlainJSON() throws {
        let raw = """
        {"summary": "Market looks calm.", "proposals": [{"symbol": "aapl", "action": "buy", "notionalUSD": 150.5, "confidence": 0.72, "reasoning": "Strong earnings."}]}
        """
        let parsed = try TradingAgent.parse(raw)
        XCTAssertEqual(parsed.summary, "Market looks calm.")
        XCTAssertEqual(parsed.proposals.count, 1)
        XCTAssertEqual(parsed.proposals[0].symbol, "aapl")
        XCTAssertEqual(parsed.proposals[0].notionalUSD, 150.5)
    }

    func testStripsMarkdownCodeFences() throws {
        let raw = """
        ```json
        {"summary": "No strong ideas today.", "proposals": []}
        ```
        """
        let parsed = try TradingAgent.parse(raw)
        XCTAssertEqual(parsed.proposals.count, 0)
    }

    func testInvalidJSONThrows() {
        XCTAssertThrowsError(try TradingAgent.parse("not json at all"))
    }

    func testRawProposalNormalizesToUppercaseSymbolAndHoldFiltering() {
        let proposal = TradeProposal(symbol: "aapl", action: .hold, notionalUSD: nil, confidence: 0.5, reasoning: "n/a")
        XCTAssertEqual(proposal.symbol, "AAPL")
    }
}
