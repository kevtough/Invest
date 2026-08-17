import Foundation

struct AlpacaOrder: Codable, Identifiable, Equatable {
    let id: String
    let symbol: String
    let qty: String?
    let notional: String?
    let side: String
    let type: String
    let timeInForce: String
    let status: String
    let filledAvgPrice: String?
    let filledQty: String?
    let createdAt: String
    let submittedAt: String?

    var createdDate: Date {
        ISO8601DateFormatter().date(from: createdAt) ?? .distantPast
    }
}
