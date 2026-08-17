import SwiftUI

struct AgentView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(TradingAgent.self) private var agent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !settings.hasAlpacaCredentials || !settings.hasAnthropicCredentials {
                    MissingCredentialsBanner(message: "Add both your Alpaca and Anthropic API keys to run the agent.")
                }

                statusCard

                Button {
                    Task { await agent.runAnalysis() }
                } label: {
                    HStack {
                        if agent.isRunning { ProgressView().controlSize(.small) }
                        Text(agent.isRunning ? "Analyzing..." : "Run Analysis Now")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(agent.isRunning || !settings.hasAlpacaCredentials || !settings.hasAnthropicCredentials)

                if let summary = agent.lastRunSummary {
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
                }

                if let error = agent.lastError {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }

                if agent.proposals.isEmpty {
                    Text("No proposals yet. Run an analysis to see AI trade ideas here — nothing executes until you approve it (unless auto-execute is on).")
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                } else {
                    VStack(spacing: 12) {
                        ForEach(agent.proposals) { proposal in
                            TradeProposalCardView(proposal: proposal)
                        }
                    }
                }
            }
            .padding()
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(settings.tradingMode.displayName, systemImage: settings.tradingMode == .live ? "exclamationmark.triangle.fill" : "checkmark.shield.fill")
                    .foregroundStyle(settings.tradingMode == .live ? .red : .green)
                Spacer()
            }
            HStack {
                Text("Auto-execute")
                Spacer()
                Text(settings.riskSettings.autoExecuteEnabled ? "ON" : "OFF")
                    .fontWeight(.semibold)
                    .foregroundStyle(settings.riskSettings.autoExecuteEnabled ? .orange : .secondary)
            }
            .font(.subheadline)
            Text(settings.riskSettings.autoExecuteEnabled
                 ? "Eligible proposals execute automatically, within your risk limits."
                 : "You'll approve or reject each proposal manually below.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct TradeProposalCardView: View {
    @Environment(TradingAgent.self) private var agent
    let proposal: TradeProposal

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(proposal.symbol).font(.headline)
                Text(proposal.action.rawValue.uppercased())
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(proposal.action == .buy ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                    .foregroundStyle(proposal.action == .buy ? .green : .red)
                    .clipShape(Capsule())
                Spacer()
                statusBadge
            }

            if let notional = proposal.notionalUSD {
                Text(Formatting.currency(notional))
                    .font(.subheadline.weight(.medium))
            }

            Text("Confidence: \(Int(proposal.confidence * 100))%")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(proposal.reasoning)
                .font(.footnote)

            if let blockReason = proposal.blockReason {
                Text(blockReason)
                    .font(.caption)
                    .foregroundStyle(proposal.status == .failed ? .red : .orange)
            }

            if proposal.status == .approved {
                HStack {
                    Button("Reject", role: .destructive) { agent.reject(proposal.id) }
                        .buttonStyle(.bordered)
                    Button("Approve & Execute") { Task { await agent.approve(proposal.id) } }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }

    private var statusBadge: some View {
        Text(statusText)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(statusColor.opacity(0.18))
            .foregroundStyle(statusColor)
            .clipShape(Capsule())
    }

    private var statusText: String {
        switch proposal.status {
        case .pending: return "PENDING"
        case .approved: return "READY"
        case .rejected: return "REJECTED"
        case .executed: return "EXECUTED"
        case .failed: return "FAILED"
        case .blocked: return "BLOCKED"
        }
    }

    private var statusColor: Color {
        switch proposal.status {
        case .pending: return .gray
        case .approved: return .blue
        case .rejected: return .gray
        case .executed: return .green
        case .failed: return .red
        case .blocked: return .orange
        }
    }
}
