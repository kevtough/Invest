import Foundation

/// Every field except `id` is optional here on purpose: newly-created or
/// under-review Alpaca accounts can return a trimmed-down account object,
/// and a single unexpectedly-absent field shouldn't take down the whole
/// Dashboard.
struct AlpacaAccount: Codable, Equatable {
    let id: String
    let status: String?
    let currency: String?
    let cash: String?
    let portfolioValue: String?
    let buyingPower: String?
    let equity: String?
    let lastEquity: String?
    let daytradeCount: Int?
    let patternDayTrader: Bool?

    var cashValue: Double { Double(cash ?? "") ?? 0 }
    var portfolioValueDouble: Double { Double(portfolioValue ?? "") ?? 0 }
    var buyingPowerValue: Double { Double(buyingPower ?? "") ?? 0 }
    var equityValue: Double { Double(equity ?? "") ?? 0 }
    var lastEquityValue: Double { Double(lastEquity ?? "") ?? 0 }

    /// Change in total account equity since the previous trading day's close.
    var dayChange: Double { equityValue - lastEquityValue }
    var dayChangePercent: Double {
        guard lastEquityValue != 0 else { return 0 }
        return dayChange / lastEquityValue
    }
}
