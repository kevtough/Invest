import Foundation

enum AlpacaError: LocalizedError {
    case missingCredentials
    case http(Int, String)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "Alpaca API key and secret are not set. Add them in Settings."
        case .http(let code, let body):
            return "Alpaca request failed (\(code)): \(body)"
        case .decoding(let error):
            return "Failed to decode Alpaca response: \(error.localizedDescription)"
        }
    }
}

/// Talks to the Alpaca Trading API (paper or live, per `SettingsStore.tradingMode`)
/// and the Alpaca Market Data API.
final class AlpacaClient {
    private let settings: SettingsStore
    private let session: URLSession

    init(settings: SettingsStore, session: URLSession = .shared) {
        self.settings = settings
        self.session = session
    }

    // MARK: - Account / Positions / Orders

    func fetchAccount() async throws -> AlpacaAccount {
        try await get(path: "/v2/account", base: settings.tradingMode.tradingBaseURL)
    }

    func fetchPositions() async throws -> [AlpacaPosition] {
        try await get(path: "/v2/positions", base: settings.tradingMode.tradingBaseURL)
    }

    func fetchOrders(status: String = "all", limit: Int = 50) async throws -> [AlpacaOrder] {
        try await get(
            path: "/v2/orders",
            base: settings.tradingMode.tradingBaseURL,
            query: [URLQueryItem(name: "status", value: status), URLQueryItem(name: "limit", value: "\(limit)")]
        )
    }

    func fetchPortfolioHistory(period: String = "1M", timeframe: String = "1D") async throws -> [PortfolioHistoryPoint] {
        let response: PortfolioHistoryResponse = try await get(
            path: "/v2/account/portfolio/history",
            base: settings.tradingMode.tradingBaseURL,
            query: [URLQueryItem(name: "period", value: period), URLQueryItem(name: "timeframe", value: timeframe)]
        )
        return zip(response.timestamp, response.equity).compactMap { ts, equity in
            guard let equity else { return nil }
            return PortfolioHistoryPoint(timestamp: ts, equity: equity)
        }
    }

    /// Places a market order sized in dollars (notional) rather than shares,
    /// so fractional buys work cleanly. Caller is responsible for guardrails.
    @discardableResult
    func placeOrder(symbol: String, side: TradeAction, notionalUSD: Double, timeInForce: String = "day") async throws -> AlpacaOrder {
        precondition(side == .buy || side == .sell, "placeOrder only supports buy/sell")
        let body: [String: Any] = [
            "symbol": symbol,
            "notional": String(format: "%.2f", notionalUSD),
            "side": side.rawValue,
            "type": "market",
            "time_in_force": timeInForce
        ]
        return try await post(path: "/v2/orders", base: settings.tradingMode.tradingBaseURL, body: body)
    }

    func cancelOrder(id: String) async throws {
        var request = URLRequest(url: settings.tradingMode.tradingBaseURL.appendingPathComponent("/v2/orders/\(id)"))
        request.httpMethod = "DELETE"
        try authenticate(&request)
        let (_, response) = try await session.data(for: request)
        try validate(response, data: Data())
    }

    // MARK: - Market Data

    func fetchLatestQuote(symbol: String) async throws -> LatestQuote {
        let response: LatestQuoteResponse = try await get(
            path: "/v2/stocks/\(symbol)/quotes/latest",
            base: settings.tradingMode.dataBaseURL
        )
        let date = ISO8601DateFormatter().date(from: response.quote.t) ?? Date()
        return LatestQuote(symbol: response.symbol, askPrice: response.quote.ap, bidPrice: response.quote.bp, timestamp: date)
    }

    func fetchLatestQuotes(symbols: [String]) async -> [String: LatestQuote] {
        var result: [String: LatestQuote] = [:]
        await withTaskGroup(of: LatestQuote?.self) { group in
            for symbol in symbols {
                group.addTask { try? await self.fetchLatestQuote(symbol: symbol) }
            }
            for await quote in group {
                if let quote { result[quote.symbol] = quote }
            }
        }
        return result
    }

    func fetchBars(symbol: String, timeframe: String = "1Day", limit: Int = 30) async throws -> [PriceBar] {
        let response: BarsResponse = try await get(
            path: "/v2/stocks/\(symbol)/bars",
            base: settings.tradingMode.dataBaseURL,
            query: [
                URLQueryItem(name: "timeframe", value: timeframe),
                URLQueryItem(name: "limit", value: "\(limit)")
            ]
        )
        return response.bars ?? []
    }

    // MARK: - Plumbing

    private func authenticate(_ request: inout URLRequest) throws {
        guard settings.hasAlpacaCredentials else { throw AlpacaError.missingCredentials }
        request.setValue(settings.alpacaKeyID, forHTTPHeaderField: "APCA-API-KEY-ID")
        request.setValue(settings.alpacaSecretKey, forHTTPHeaderField: "APCA-API-SECRET-KEY")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }

    private func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw AlpacaError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }

    private func get<T: Decodable>(path: String, base: URL, query: [URLQueryItem] = []) async throws -> T {
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        try authenticate(&request)
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(T.self, from: data)
        } catch {
            throw AlpacaError.decoding(error)
        }
    }

    private func post<T: Decodable>(path: String, base: URL, body: [String: Any]) async throws -> T {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = "POST"
        try authenticate(&request)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(T.self, from: data)
        } catch {
            throw AlpacaError.decoding(error)
        }
    }
}
