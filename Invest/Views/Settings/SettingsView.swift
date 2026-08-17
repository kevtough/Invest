import SwiftUI

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settingsEnv
    @State private var showLiveConfirmation = false
    @State private var showAutoExecuteConfirmation = false
    @State private var pendingMode: TradingMode?

    var body: some View {
        @Bindable var settings = settingsEnv
        Form {
            Section {
                Text("This app is for personal use only. It is not financial advice. Automated and AI-assisted trading can lose money, including through bugs, bad data, or model mistakes. You are solely responsible for everything it does with your brokerage account.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Brokerage (Alpaca)") {
                SecureField("API Key ID", text: $settings.alpacaKeyID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("API Secret Key", text: $settings.alpacaSecretKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Picker("Trading Mode", selection: Binding(
                    get: { settings.tradingMode },
                    set: { newMode in
                        if newMode == .live && settings.tradingMode != .live {
                            pendingMode = newMode
                            showLiveConfirmation = true
                        } else {
                            settings.tradingMode = newMode
                        }
                    }
                )) {
                    ForEach(TradingMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if settings.tradingMode == .live {
                    Label("Live mode places real orders with real money.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("AI (Anthropic Claude)") {
                SecureField("Anthropic API Key", text: $settings.anthropicAPIKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Model", text: $settings.claudeModel)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Text("Must match a model id available on your Anthropic account.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("AI Trading Agent Guardrails") {
                Toggle("Auto-execute approved proposals", isOn: Binding(
                    get: { settings.riskSettings.autoExecuteEnabled },
                    set: { newValue in
                        if newValue {
                            showAutoExecuteConfirmation = true
                        } else {
                            settings.riskSettings.autoExecuteEnabled = false
                        }
                    }
                ))

                riskStepper(
                    title: "Max trades / day",
                    value: $settings.riskSettings.maxTradesPerDay,
                    range: 1...20
                )

                riskDoubleField(
                    title: "Max $ per order",
                    value: $settings.riskSettings.maxOrderNotionalUSD
                )

                VStack(alignment: .leading) {
                    Text("Max % of portfolio per order: \(Int(settings.riskSettings.maxPositionPercentOfPortfolio * 100))%")
                        .font(.subheadline)
                    Slider(value: $settings.riskSettings.maxPositionPercentOfPortfolio, in: 0.01...0.5, step: 0.01)
                }

                VStack(alignment: .leading) {
                    Text("Min confidence to execute: \(Int(settings.riskSettings.minConfidenceToExecute * 100))%")
                        .font(.subheadline)
                    Slider(value: $settings.riskSettings.minConfidenceToExecute, in: 0.0...1.0, step: 0.05)
                }
            }

            Section {
                Text("The agent only ever trades symbols in your Watchlist or existing positions, unless you set an explicit allowed-symbols list.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationBarTitleDisplayMode(.large)
        .confirmationDialog(
            "Switch to Live Trading?",
            isPresented: $showLiveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Switch to Live (Real Money)", role: .destructive) {
                if let mode = pendingMode { settings.tradingMode = mode }
                pendingMode = nil
            }
            Button("Cancel", role: .cancel) { pendingMode = nil }
        } message: {
            Text("Orders placed after this point — manually or by the AI agent — will use real money in your live Alpaca account.")
        }
        .confirmationDialog(
            "Enable Auto-Execute?",
            isPresented: $showAutoExecuteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Enable Auto-Execute", role: .destructive) {
                settings.riskSettings.autoExecuteEnabled = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The AI agent will place orders automatically whenever a proposal passes your risk guardrails, without asking you first. You can turn this off at any time.")
        }
    }

    private func riskStepper(title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        Stepper("\(title): \(value.wrappedValue)", value: value, in: range)
    }

    private func riskDoubleField(title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 100)
        }
    }
}
