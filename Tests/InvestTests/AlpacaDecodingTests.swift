import XCTest
@testable import Invest

final class AlpacaDecodingTests: XCTestCase {
    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    func testDecodesAccountFromSnakeCaseJSON() throws {
        let json = """
        {
          "id": "abc123",
          "status": "ACTIVE",
          "currency": "USD",
          "cash": "1234.56",
          "portfolio_value": "10000.00",
          "buying_power": "20000.00",
          "equity": "10000.00",
          "last_equity": "9800.00",
          "daytrade_count": 1,
          "pattern_day_trader": false
        }
        """.data(using: .utf8)!

        let account = try decoder.decode(AlpacaAccount.self, from: json)
        XCTAssertEqual(account.equityValue, 10000.00, accuracy: 0.001)
        XCTAssertEqual(account.lastEquityValue, 9800.00, accuracy: 0.001)
        XCTAssertEqual(account.dayChange, 200.00, accuracy: 0.001)
    }

    func testDecodesPositionFromSnakeCaseJSON() throws {
        let json = """
        {
          "symbol": "AAPL",
          "qty": "10",
          "side": "long",
          "avg_entry_price": "150.00",
          "current_price": "165.00",
          "market_value": "1650.00",
          "unrealized_pl": "150.00",
          "unrealized_plpc": "0.10",
          "cost_basis": "1500.00"
        }
        """.data(using: .utf8)!

        let position = try decoder.decode(AlpacaPosition.self, from: json)
        XCTAssertEqual(position.marketValueDouble, 1650.00, accuracy: 0.001)
        XCTAssertEqual(position.unrealizedPLPercent, 0.10, accuracy: 0.001)
    }
}
