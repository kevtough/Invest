# Invest

A personal, AI-assisted investment app for iPad (13") and iPhone Pro Max. Native
SwiftUI, universal iPhone/iPad layout, iOS 17+.

**⚠️ For personal use only. Not financial advice. Automated and AI-assisted
trading can lose real money** — through bugs, bad data, API outages, or the
model simply being wrong. Read [Safety model](#safety-model) before turning on
live trading or auto-execute.

## What it does

- **Dashboard** — account equity, day P/L, an equity curve, and current positions,
  pulled live from your brokerage.
- **Watchlist** — add/remove symbols, live bid/ask quotes, tap a symbol for a
  30-day price chart.
- **Research Chat** — free-form chat with Claude about stocks, sectors, or your
  portfolio. Discussion only — this screen never places trades.
- **AI Agent** — the automated part. On demand (`Run Analysis Now`), it sends
  your account, positions, and watchlist quotes to Claude, gets back trade
  ideas as strict JSON, and runs each one through risk guardrails. Proposals
  that pass show up as cards you approve or reject; if you've explicitly
  enabled auto-execute in Settings, eligible ones place automatically instead.
- **Orders** — order history from your brokerage.
- **Settings** — API keys (stored in the iOS Keychain, never in code or
  UserDefaults), paper/live trading toggle, and every risk guardrail.

## Architecture

- SwiftUI + the `Observable` macro (iOS 17), async/await networking, no
  third-party dependencies.
- **Brokerage**: [Alpaca](https://alpaca.markets) — commission-free, built for
  API-driven trading, with a free paper-trading (simulated money) environment
  and a live environment behind the same API shape.
- **AI**: the Anthropic Claude API, called directly from the app with your own
  API key.
- Project files are generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen)
  from `project.yml` rather than committing a raw `.xcodeproj`, so the diff
  stays readable and there's nothing machine-specific checked in.

```
Invest/
  App/        entry point, DI container (AppState), adaptive root shell
  Models/     Codable types for Alpaca + the AI agent's structured output
  Services/   AlpacaClient, AnthropicClient, TradingAgent, Keychain, stores
  Views/      Dashboard, Watchlist, Chat, Agent, Orders, Settings
Tests/
  InvestTests/  guardrail + JSON-parsing unit tests
```

## Safety model

Nothing places an order without going through **all** of these layers:

1. Claude never has a "place order" tool — it only ever returns a JSON opinion
   (`{"proposals": [...]}`). It has no way to act directly on your account.
2. Every proposal is checked in Swift, in `TradingAgent.applyGuardrails`,
   against: minimum confidence, an allowed-symbols list (defaults to your
   watchlist + existing positions only), a max dollar amount per order, a max
   % of portfolio per order, and a max number of agent trades per day. Any
   failure marks the proposal `blocked` with a human-readable reason and it
   goes no further.
3. A proposal that passes guardrails still needs a tap on **Approve & Execute**
   in the Agent tab — *unless* you've explicitly turned on **Auto-execute** in
   Settings (off by default, and gated behind its own confirmation dialog).
4. The **daily trade cap** is re-checked immediately before an order is
   submitted, not just when the proposal was generated.
5. **Trading Mode defaults to Paper** (simulated money). Switching to **Live**
   requires an explicit confirmation dialog that says, in plain language, that
   it places real orders with real money.

You control all the thresholds in Settings → AI Trading Agent Guardrails.

## Setup

### 1. Get your API keys

- **Alpaca**: sign up at [alpaca.markets](https://alpaca.markets), generate a
  **paper trading** API key/secret first (Dashboard → Paper Trading → API
  Keys). Don't touch live keys until you trust the app.
- **Anthropic**: create a key at [console.anthropic.com](https://console.anthropic.com).

You'll paste both into the app's Settings screen after it's installed — they're
stored in the iOS Keychain, not in this repo or in UserDefaults.

### 2. Generate the Xcode project (on a Mac)

```bash
brew install xcodegen
cd Invest
xcodegen generate
open Invest.xcodeproj
```

### 3. Run it on your devices

1. In Xcode, select the `Invest` target → **Signing & Capabilities** → set your
   Apple ID as the team (a free personal team works for sideloading to your
   own devices).
2. Plug in your iPad (13") or iPhone Pro Max, select it as the run destination,
   and hit Run. First launch on-device requires trusting your developer
   certificate under **Settings → General → VPN & Device Management**.
3. It's a universal app — the same build adapts its layout (sidebar on iPad,
   tab bar on iPhone) automatically.
4. Open **Settings** in the app, add your Alpaca and Anthropic keys, confirm
   **Trading Mode: Paper**, and try **Run Analysis Now** in the Agent tab.

### 4. Running tests

In Xcode: `Cmd+U` on the `Invest` scheme. Or from the CLI:

```bash
xcodebuild test -project Invest.xcodeproj -scheme Invest -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)'
```

## Unattended automation (GitHub Actions)

The iOS app only runs the agent when you tap "Run Analysis Now" — nothing
happens while it's closed. For fully unattended operation (the agent checks
the market and trades on its own schedule, no phone or Mac needs to be on),
`.github/workflows/trading-agent.yml` runs `scripts/run_trading_agent.py` on
a cron schedule directly on GitHub's infrastructure. It re-implements the
same guardrail logic as `TradingAgent.swift`, so scheduled runs behave the
same way manual ones do.

### Setup

1. In this repo on GitHub: **Settings → Secrets and variables → Actions →
   New repository secret**. Add three secrets:
   - `ALPACA_KEY_ID`
   - `ALPACA_SECRET_KEY`
   - `ANTHROPIC_API_KEY`

   Use the same paper-trading Alpaca keys and Anthropic key from the app's
   Settings screen (or separate ones — either works, they're independent).
2. Edit `config/risk-settings.json` (directly on GitHub.com, no Xcode
   needed) to set your watchlist and risk limits. It ships with the same
   defaults as the app: $5,000 max per order, $10,000 lifetime auto-invested
   cap, 20% of portfolio per order, 55% minimum confidence, 5 trades/day,
   paper trading mode, auto-execute on.
3. The workflow runs every 30 minutes on weekdays during roughly US market
   hours. To trigger a run immediately without waiting: go to the
   **Actions** tab → **AI Trading Agent** → **Run workflow**.

### Monitoring

- **Actions tab**: every run's logs (what the agent proposed, what got
  blocked and why, what executed) are viewable there, plus email
  notifications on failure if you have those enabled on your GitHub account.
- **`logs/agent-runs.jsonl`**: each run also appends a JSON summary here,
  committed back to the repo automatically — a permanent, greppable history
  beyond GitHub Actions' log retention window.
- **The iOS app itself**: Dashboard and Orders still reflect real account
  state regardless of what triggered a trade, since everything lands in the
  same Alpaca account either way.

### Safety notes specific to automation

- Defaults to **paper trading** — change `tradingMode` in
  `config/risk-settings.json` to `"live"` only when you deliberately want
  real-money automated trading, and reconsider your risk limits first.
- Every order the script places is tagged with a `client_order_id` prefix
  (`aiagent-`), which is how daily/lifetime trade caps are tracked — manual
  trades from the iOS app don't count against those automated-only limits.
- Disabling automation entirely: turn off the schedule by commenting out (or
  deleting) the `schedule:` trigger in the workflow file, or disable the
  workflow from the Actions tab.

## Notes / limitations

- No App Store distribution — this is a sideloaded personal app, re-signed via
  Xcode every ~7 days on a free Apple ID (or indefinitely with a paid
  developer account).
- Market data comes from Alpaca's own data API, so no second data-provider key
  is needed.
- The Claude model id is configurable in Settings (defaults to
  `claude-sonnet-5`) since available model ids depend on your Anthropic account.
