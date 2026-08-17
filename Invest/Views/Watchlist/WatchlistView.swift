import SwiftUI

struct WatchlistView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(WatchlistStore.self) private var watchlist
    @State private var newSymbol = ""

    var body: some View {
        VStack(spacing: 0) {
            if !settings.hasAlpacaCredentials {
                MissingCredentialsBanner(message: "Add your Alpaca API keys to see live quotes.")
                    .padding()
            }

            HStack {
                TextField("Add symbol (e.g. TSLA)", text: $newSymbol)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    watchlist.addSymbol(newSymbol)
                    newSymbol = ""
                }
                .disabled(newSymbol.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()

            List {
                ForEach(settings.watchlist, id: \.self) { symbol in
                    NavigationLink {
                        SymbolDetailView(symbol: symbol, quote: watchlist.quotes[symbol])
                    } label: {
                        WatchlistRow(symbol: symbol, quote: watchlist.quotes[symbol])
                    }
                }
                .onDelete { offsets in
                    for index in offsets {
                        watchlist.removeSymbol(settings.watchlist[index])
                    }
                }
            }
            .listStyle(.plain)
        }
        .refreshable { await watchlist.refresh() }
        .task { await watchlist.refresh() }
    }
}

private struct WatchlistRow: View {
    let symbol: String
    let quote: LatestQuote?

    var body: some View {
        HStack {
            Text(symbol).font(.subheadline.weight(.semibold))
            Spacer()
            if let quote {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Formatting.currency(quote.midPrice)).font(.subheadline.weight(.medium))
                    Text("bid \(String(format: "%.2f", quote.bidPrice)) / ask \(String(format: "%.2f", quote.askPrice))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}
