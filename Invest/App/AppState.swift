import Foundation

/// Wires together every store/service and hands them out via the environment.
/// Created once at app launch.
@MainActor
final class AppState {
    let settings: SettingsStore
    let alpaca: AlpacaClient
    let claude: AnthropicClient
    let portfolio: PortfolioStore
    let watchlist: WatchlistStore
    let chat: ChatStore
    let agent: TradingAgent

    init() {
        let settings = SettingsStore()
        let alpaca = AlpacaClient(settings: settings)
        let claude = AnthropicClient(settings: settings)

        self.settings = settings
        self.alpaca = alpaca
        self.claude = claude
        self.portfolio = PortfolioStore(alpaca: alpaca)
        self.watchlist = WatchlistStore(alpaca: alpaca, settings: settings)
        self.chat = ChatStore(claude: claude, alpaca: alpaca, settings: settings)
        self.agent = TradingAgent(alpaca: alpaca, claude: claude, settings: settings)
    }
}
