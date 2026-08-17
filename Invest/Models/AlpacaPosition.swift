import Foundation

struct AlpacaPosition: Codable, Identifiable, Equatable {
    var id: String { symbol }

    let symbol: String
    let qty: String
    let side: String
    let avgEntryPrice: String
    let currentPrice: String?
    let marketValue: String?
    let unrealizedPl: String?
    let unrealizedPlpc: String?
    let costBasis: String?

    var qtyValue: Double { Double(qty) ?? 0 }
    var avgEntryPriceValue: Double { Double(avgEntryPrice) ?? 0 }
    var currentPriceValue: Double { Double(currentPrice ?? "") ?? avgEntryPriceValue }
    var marketValueDouble: Double { Double(marketValue ?? "") ?? 0 }
    var unrealizedPLValue: Double { Double(unrealizedPl ?? "") ?? 0 }
    var unrealizedPLPercent: Double { Double(unrealizedPlpc ?? "") ?? 0 }
}
