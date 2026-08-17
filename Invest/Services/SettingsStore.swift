import Foundation
import Observation

/// Central store for user-configurable, non-secret preferences (UserDefaults)
/// plus a thin façade over the Keychain-stored API credentials.
@Observable
final class SettingsStore {
    var tradingMode: TradingMode {
        didSet { UserDefaults.standard.set(tradingMode.rawValue, forKey: Keys.tradingMode) }
    }

    var riskSettings: RiskSettings {
        didSet {
            if let data = try? JSONEncoder().encode(riskSettings) {
                UserDefaults.standard.set(data, forKey: Keys.riskSettings)
            }
        }
    }

    var watchlist: [String] {
        didSet { UserDefaults.standard.set(watchlist, forKey: Keys.watchlist) }
    }

    /// Claude model id used for chat and the trading agent. Configurable since
    /// available model ids change over time and access varies by account.
    var claudeModel: String {
        didSet { UserDefaults.standard.set(claudeModel, forKey: Keys.claudeModel) }
    }

    var alpacaKeyID: String {
        didSet { KeychainService.set(alpacaKeyID, for: KeychainService.Key.alpacaKeyID) }
    }

    var alpacaSecretKey: String {
        didSet { KeychainService.set(alpacaSecretKey, for: KeychainService.Key.alpacaSecretKey) }
    }

    var anthropicAPIKey: String {
        didSet { KeychainService.set(anthropicAPIKey, for: KeychainService.Key.anthropicAPIKey) }
    }

    var hasAlpacaCredentials: Bool { !alpacaKeyID.isEmpty && !alpacaSecretKey.isEmpty }
    var hasAnthropicCredentials: Bool { !anthropicAPIKey.isEmpty }

    private enum Keys {
        static let tradingMode = "settings.tradingMode"
        static let riskSettings = "settings.riskSettings"
        static let watchlist = "settings.watchlist"
        static let claudeModel = "settings.claudeModel"
    }

    init() {
        let defaults = UserDefaults.standard
        self.tradingMode = TradingMode(rawValue: defaults.string(forKey: Keys.tradingMode) ?? "") ?? .paper
        if let data = defaults.data(forKey: Keys.riskSettings),
           let decoded = try? JSONDecoder().decode(RiskSettings.self, from: data) {
            self.riskSettings = decoded
        } else {
            self.riskSettings = .default
        }
        self.watchlist = defaults.stringArray(forKey: Keys.watchlist) ?? ["AAPL", "MSFT", "NVDA", "SPY"]
        self.claudeModel = defaults.string(forKey: Keys.claudeModel) ?? "claude-sonnet-5"
        self.alpacaKeyID = KeychainService.get(KeychainService.Key.alpacaKeyID) ?? ""
        self.alpacaSecretKey = KeychainService.get(KeychainService.Key.alpacaSecretKey) ?? ""
        self.anthropicAPIKey = KeychainService.get(KeychainService.Key.anthropicAPIKey) ?? ""
    }
}
