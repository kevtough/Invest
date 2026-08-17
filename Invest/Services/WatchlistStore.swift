import Foundation
import Observation

/// Holds live quotes for the user's watchlist symbols (from `SettingsStore`).
@Observable
final class WatchlistStore {
    private let alpaca: AlpacaClient
    private let settings: SettingsStore

    var quotes: [String: LatestQuote] = [:]
    var isLoading = false
    var lastError: String?

    init(alpaca: AlpacaClient, settings: SettingsStore) {
        self.alpaca = alpaca
        self.settings = settings
    }

    func refresh() async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        guard !settings.watchlist.isEmpty else { quotes = [:]; return }
        quotes = await alpaca.fetchLatestQuotes(symbols: settings.watchlist)
    }

    func addSymbol(_ symbol: String) {
        let symbol = symbol.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !symbol.isEmpty, !settings.watchlist.contains(symbol) else { return }
        settings.watchlist.append(symbol)
        Task { await refresh() }
    }

    func removeSymbol(_ symbol: String) {
        settings.watchlist.removeAll { $0 == symbol }
        quotes[symbol] = nil
    }

    func fetchBars(symbol: String) async throws -> [PriceBar] {
        try await alpaca.fetchBars(symbol: symbol, timeframe: "1Day", limit: 30)
    }
}
