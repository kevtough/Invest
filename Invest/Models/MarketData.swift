import Foundation

/// A single latest bid/ask quote for a symbol, from Alpaca's market data API.
struct LatestQuote: Equatable {
    let symbol: String
    let askPrice: Double
    let bidPrice: Double
    let timestamp: Date

    /// Simple mid-point used for display/estimation purposes.
    var midPrice: Double { (askPrice + bidPrice) / 2 }
}

struct LatestQuoteResponse: Codable {
    let symbol: String
    let quote: RawQuote
}

struct RawQuote: Codable {
    let ap: Double
    let bp: Double
    let t: String
}

/// A single OHLCV bar, used for sparkline/history charts.
struct PriceBar: Codable, Identifiable, Equatable {
    var id: String { t }
    let t: String
    let o: Double
    let h: Double
    let l: Double
    let c: Double
    let v: Double

    var date: Date {
        ISO8601DateFormatter().date(from: t) ?? .distantPast
    }
}

struct BarsResponse: Codable {
    let bars: [PriceBar]?
    let symbol: String
}

/// One point in the account's historical equity curve.
struct PortfolioHistoryPoint: Identifiable, Equatable {
    var id: TimeInterval { timestamp }
    let timestamp: TimeInterval
    let equity: Double

    var date: Date { Date(timeIntervalSince1970: timestamp) }
}

struct PortfolioHistoryResponse: Codable {
    let timestamp: [TimeInterval]
    let equity: [Double?]
}
