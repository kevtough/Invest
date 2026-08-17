import Foundation
import Observation

/// Holds the fetched account/positions/orders/history state shared across views.
@Observable
final class PortfolioStore {
    private let alpaca: AlpacaClient

    var account: AlpacaAccount?
    var positions: [AlpacaPosition] = []
    var orders: [AlpacaOrder] = []
    var history: [PortfolioHistoryPoint] = []
    var isLoading = false
    var lastError: String?

    init(alpaca: AlpacaClient) {
        self.alpaca = alpaca
    }

    /// Each piece is fetched independently so that one endpoint failing
    /// (e.g. portfolio history on a brand-new account with no trades yet)
    /// doesn't blank out data the other calls successfully returned.
    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        var firstError: String?

        do {
            account = try await alpaca.fetchAccount()
        } catch {
            firstError = firstError ?? error.localizedDescription
        }
        do {
            positions = try await alpaca.fetchPositions()
        } catch {
            firstError = firstError ?? error.localizedDescription
        }
        do {
            orders = try await alpaca.fetchOrders()
        } catch {
            firstError = firstError ?? error.localizedDescription
        }
        do {
            history = try await alpaca.fetchPortfolioHistory()
        } catch {
            // Non-fatal: a new account with no trading activity yet may not
            // have a history endpoint response in the expected shape.
            history = []
        }

        lastError = firstError
    }
}
