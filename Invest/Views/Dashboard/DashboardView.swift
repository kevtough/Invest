import SwiftUI
import Charts

struct DashboardView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(PortfolioStore.self) private var portfolio

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !settings.hasAlpacaCredentials {
                    MissingCredentialsBanner(message: "Add your Alpaca API keys to see live portfolio data.")
                }

                TradingModeTag(mode: settings.tradingMode)

                if let account = portfolio.account {
                    AccountSummaryCard(account: account)
                }

                if portfolio.history.count > 1 {
                    EquityChartCard(history: portfolio.history)
                }

                if let error = portfolio.lastError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Positions")
                        .font(.headline)
                    if portfolio.positions.isEmpty {
                        Text("No open positions.")
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(portfolio.positions) { position in
                                PositionRowView(position: position)
                                Divider()
                            }
                        }
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .padding()
        }
        .refreshable { await portfolio.refresh() }
        .task { await portfolio.refresh() }
        .navigationBarTitleDisplayMode(.large)
    }
}

private struct TradingModeTag: View {
    let mode: TradingMode

    var body: some View {
        HStack {
            Circle()
                .fill(mode == .live ? .red : .green)
                .frame(width: 8, height: 8)
            Text(mode == .live ? "LIVE TRADING - Real Money" : "Paper Trading - Simulated")
                .font(.caption.weight(.semibold))
                .foregroundStyle(mode == .live ? .red : .secondary)
        }
    }
}

private struct AccountSummaryCard: View {
    let account: AlpacaAccount

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Formatting.currency(account.equityValue))
                .font(.system(size: 34, weight: .bold, design: .rounded))
            HStack(spacing: 6) {
                Image(systemName: account.dayChange >= 0 ? "arrow.up.right" : "arrow.down.right")
                Text("\(Formatting.currency(account.dayChange)) (\(Formatting.percent(account.dayChangePercent))) today")
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(account.dayChange >= 0 ? .green : .red)

            HStack(spacing: 24) {
                statColumn("Cash", Formatting.currency(account.cashValue))
                statColumn("Buying Power", Formatting.currency(account.buyingPowerValue))
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
    }

    private func statColumn(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold))
        }
    }
}

private struct EquityChartCard: View {
    let history: [PortfolioHistoryPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Equity (1 Month)")
                .font(.headline)
            Chart(history) { point in
                LineMark(x: .value("Date", point.date), y: .value("Equity", point.equity))
                    .interpolationMethod(.monotone)
                AreaMark(x: .value("Date", point.date), y: .value("Equity", point.equity))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(.linearGradient(colors: [.accentColor.opacity(0.25), .clear], startPoint: .top, endPoint: .bottom))
            }
            .chartYAxis { AxisMarks(position: .trailing) }
            .frame(height: 180)
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct PositionRowView: View {
    let position: AlpacaPosition

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(position.symbol).font(.subheadline.weight(.semibold))
                Text("\(position.qty) sh @ \(Formatting.currency(position.avgEntryPriceValue))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Formatting.currency(position.marketValueDouble))
                    .font(.subheadline.weight(.medium))
                Text(Formatting.percent(position.unrealizedPLPercent))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(position.unrealizedPLValue >= 0 ? .green : .red)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
}
