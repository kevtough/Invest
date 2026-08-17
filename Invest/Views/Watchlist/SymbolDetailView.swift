import SwiftUI
import Charts

struct SymbolDetailView: View {
    let symbol: String
    let quote: LatestQuote?

    @Environment(WatchlistStore.self) private var watchlist
    @State private var bars: [PriceBar] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let quote {
                    Text(Formatting.currency(quote.midPrice))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("bid \(String(format: "%.2f", quote.bidPrice))  ·  ask \(String(format: "%.2f", quote.askPrice))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if isLoading {
                    ProgressView().frame(maxWidth: .infinity)
                } else if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                } else if bars.isEmpty {
                    Text("No price history available.").foregroundStyle(.secondary)
                } else {
                    Chart(bars) { bar in
                        LineMark(x: .value("Date", bar.date), y: .value("Close", bar.c))
                            .interpolationMethod(.monotone)
                    }
                    .frame(height: 220)
                    .padding(.vertical, 8)
                }
            }
            .padding()
        }
        .navigationTitle(symbol)
        .task { await loadBars() }
    }

    private func loadBars() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            bars = try await watchlist.fetchBars(symbol: symbol)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
