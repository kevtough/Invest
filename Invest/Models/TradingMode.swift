import Foundation

/// Which Alpaca environment the app talks to. Paper is simulated money;
/// Live places real orders against a real brokerage account.
enum TradingMode: String, Codable, CaseIterable, Identifiable {
    case paper
    case live

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .paper: return "Paper (Simulated)"
        case .live: return "Live (Real Money)"
        }
    }

    var tradingBaseURL: URL {
        switch self {
        case .paper: return URL(string: "https://paper-api.alpaca.markets")!
        case .live: return URL(string: "https://api.alpaca.markets")!
        }
    }

    /// Market data is served from the same host regardless of paper/live.
    var dataBaseURL: URL {
        URL(string: "https://data.alpaca.markets")!
    }
}
