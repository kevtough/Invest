import SwiftUI

struct OrdersView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(PortfolioStore.self) private var portfolio

    var body: some View {
        List {
            if !settings.hasAlpacaCredentials {
                MissingCredentialsBanner(message: "Add your Alpaca API keys to see order history.")
                    .listRowSeparator(.hidden)
            }
            if portfolio.orders.isEmpty {
                Text("No orders yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(portfolio.orders) { order in
                    OrderRow(order: order)
                }
            }
        }
        .listStyle(.plain)
        .refreshable { await portfolio.refresh() }
        .task { if portfolio.orders.isEmpty { await portfolio.refresh() } }
    }
}

private struct OrderRow: View {
    let order: AlpacaOrder

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(order.symbol).font(.subheadline.weight(.semibold))
                Text(order.side.uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(order.side == "buy" ? .green : .red)
                Spacer()
                Text(order.status.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                if let notional = order.notional {
                    Text("$\(notional) notional")
                } else if let qty = order.qty {
                    Text("\(qty) shares")
                }
                if let filledPrice = order.filledAvgPrice {
                    Text("· filled @ \(filledPrice)")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Text(order.createdDate.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}
