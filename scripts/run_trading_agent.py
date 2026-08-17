#!/usr/bin/env python3
"""
Unattended trading agent runner, meant to be invoked on a schedule by
GitHub Actions (see .github/workflows/trading-agent.yml).

Mirrors the guardrail logic in Invest/Services/TradingAgent.swift so that
automated runs behave the same way as manually tapping "Run Analysis Now"
in the iOS app. Reads its configuration from config/risk-settings.json,
which is safe to edit directly on GitHub.com -- no Xcode needed to tune
the watchlist or risk limits.

Required environment variables (set as GitHub Actions secrets):
  ALPACA_KEY_ID
  ALPACA_SECRET_KEY
  ANTHROPIC_API_KEY
"""

import json
import os
import re
import sys
import urllib.request
import urllib.error
from datetime import datetime, timezone

CONFIG_PATH = os.path.join(os.path.dirname(__file__), "..", "config", "risk-settings.json")
LOG_PATH = os.path.join(os.path.dirname(__file__), "..", "logs", "agent-runs.jsonl")

# Every order this script places is tagged with this prefix so we can tell
# agent-initiated orders apart from ones you place manually in the app,
# for the purposes of the daily/lifetime trade caps below.
CLIENT_ORDER_ID_PREFIX = "aiagent-"

ANTHROPIC_API_URL = "https://api.anthropic.com/v1/messages"
ANTHROPIC_VERSION = "2023-06-01"

SYSTEM_PROMPT = """You are an investment research assistant embedded in a personal automated trading system. \
You analyze a user's portfolio and watchlist and propose trades. You do NOT place trades yourself - the \
system applies its own risk rules before anything executes. Be conservative: prefer to propose nothing \
unless you have a clear, well-reasoned idea, and never propose more than a few trades at once. Always reply \
with ONLY a single JSON object, no markdown fences, no prose outside the JSON, matching exactly this shape:
{"summary": "one or two sentence overview", "proposals": [{"symbol": "AAPL", "action": "buy", "notionalUSD": 100.0, "confidence": 0.7, "reasoning": "short explanation"}]}
"action" must be "buy" or "sell". Omit a symbol entirely instead of proposing to hold it. "confidence" is your \
own calibrated 0.0-1.0 estimate of how strong the idea is. "notionalUSD" is the dollar amount to trade, not a \
share count."""


def load_config():
    with open(CONFIG_PATH) as f:
        return json.load(f)


def alpaca_base_url(trading_mode):
    return "https://paper-api.alpaca.markets" if trading_mode == "paper" else "https://api.alpaca.markets"


def alpaca_request(method, url, key_id, secret_key, body=None):
    headers = {
        "APCA-API-KEY-ID": key_id,
        "APCA-API-SECRET-KEY": secret_key,
        "Content-Type": "application/json",
    }
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode())


def fetch_account(base, key_id, secret_key):
    return alpaca_request("GET", f"{base}/v2/account", key_id, secret_key)


def fetch_positions(base, key_id, secret_key):
    return alpaca_request("GET", f"{base}/v2/positions", key_id, secret_key)


def fetch_todays_agent_orders(base, key_id, secret_key):
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    url = f"{base}/v2/orders?status=all&after={today}T00:00:00Z&limit=200"
    orders = alpaca_request("GET", url, key_id, secret_key)
    return [o for o in orders if (o.get("client_order_id") or "").startswith(CLIENT_ORDER_ID_PREFIX)]


def fetch_all_agent_orders(base, key_id, secret_key):
    url = f"{base}/v2/orders?status=all&limit=500"
    orders = alpaca_request("GET", url, key_id, secret_key)
    return [o for o in orders if (o.get("client_order_id") or "").startswith(CLIENT_ORDER_ID_PREFIX)]


def fetch_latest_quote(data_base, key_id, secret_key, symbol):
    try:
        resp = alpaca_request("GET", f"{data_base}/v2/stocks/{symbol}/quotes/latest", key_id, secret_key)
        q = resp.get("quote", {})
        return {"bid": q.get("bp"), "ask": q.get("ap")}
    except Exception:
        return None


def place_order(base, key_id, secret_key, symbol, side, notional):
    body = {
        "symbol": symbol,
        "notional": f"{notional:.2f}",
        "side": side,
        "type": "market",
        "time_in_force": "day",
        "client_order_id": f"{CLIENT_ORDER_ID_PREFIX}{int(datetime.now(timezone.utc).timestamp())}-{symbol}",
    }
    return alpaca_request("POST", f"{base}/v2/orders", key_id, secret_key, body)


def build_prompt(account, positions, quotes, watchlist):
    lines = []
    equity = float(account.get("equity") or 0)
    cash = float(account.get("cash") or 0)
    buying_power = float(account.get("buying_power") or 0)
    lines.append(f"Account: equity=${equity:.2f}, cash=${cash:.2f}, buying_power=${buying_power:.2f}")
    lines.append("")
    lines.append("Current positions:")
    if not positions:
        lines.append("(none)")
    else:
        for p in positions:
            pl_pct = float(p.get("unrealized_plpc") or 0) * 100
            lines.append(
                f"- {p['symbol']}: qty={p['qty']}, avg_entry={p['avg_entry_price']}, "
                f"current={p.get('current_price', '?')}, unrealized_pl={p.get('unrealized_pl', '0')} ({pl_pct:.1f}%)"
            )
    lines.append("")
    lines.append("Watchlist quotes:")
    for symbol in watchlist:
        q = quotes.get(symbol)
        if q:
            lines.append(f"- {symbol}: bid={q['bid']}, ask={q['ask']}")
        else:
            lines.append(f"- {symbol}: quote unavailable")
    return "\n".join(lines)


def call_claude(api_key, model, prompt):
    body = {
        "model": model,
        "max_tokens": 2048,
        "system": SYSTEM_PROMPT,
        "messages": [{"role": "user", "content": prompt}],
    }
    req = urllib.request.Request(
        ANTHROPIC_API_URL,
        data=json.dumps(body).encode(),
        headers={
            "x-api-key": api_key,
            "anthropic-version": ANTHROPIC_VERSION,
            "content-type": "application/json",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        parsed = json.loads(resp.read().decode())
    return "".join(block.get("text", "") for block in parsed.get("content", []))


def parse_agent_response(text):
    text = text.strip()
    if text.startswith("```"):
        text = re.sub(r"^```(json)?", "", text).strip()
        text = re.sub(r"```$", "", text).strip()
    return json.loads(text)


def apply_guardrails(proposal, config, account, positions, todays_agent_orders, all_agent_orders):
    symbol = proposal["symbol"].upper()
    action = proposal["action"].lower()
    notional = proposal.get("notionalUSD")
    confidence = proposal.get("confidence", 0)

    if not notional or notional <= 0:
        return False, "Missing or invalid order size."

    if confidence < config["minConfidenceToExecute"]:
        return False, f"Confidence {confidence*100:.0f}% is below minimum of {config['minConfidenceToExecute']*100:.0f}%."

    allowed = config.get("allowedSymbols") or []
    watchlist = config.get("watchlist") or []
    held_symbols = {p["symbol"] for p in positions}
    if allowed:
        if symbol not in allowed:
            return False, f"{symbol} is not in the allowed symbols list."
    else:
        if symbol not in watchlist and symbol not in held_symbols:
            return False, f"{symbol} is not on the watchlist or in positions."

    if notional > config["maxOrderNotionalUSD"]:
        return False, f"${notional:.0f} exceeds max order size of ${config['maxOrderNotionalUSD']:.0f}."

    portfolio_value = float(account.get("portfolio_value") or 0)
    max_by_pct = portfolio_value * config["maxPositionPercentOfPortfolio"]
    if notional > max_by_pct:
        return False, f"${notional:.0f} exceeds {config['maxPositionPercentOfPortfolio']*100:.0f}% of portfolio (${max_by_pct:.0f})."

    max_total = config.get("maxTotalInvestedUSD")
    if max_total is not None:
        already_invested = sum(float(o.get("notional") or 0) for o in all_agent_orders if o.get("side") == "buy")
        if already_invested + notional > max_total:
            return False, f"Would exceed lifetime auto-invested cap of ${max_total:.0f} (already ${already_invested:.0f})."

    if action == "sell":
        held = next((p for p in positions if p["symbol"] == symbol), None)
        if not held or float(held.get("market_value") or 0) <= 0:
            return False, f"No existing position in {symbol} to sell."

    if len(todays_agent_orders) >= config["maxTradesPerDay"]:
        return False, f"Daily trade limit of {config['maxTradesPerDay']} already reached."

    return True, None


def main():
    key_id = os.environ["ALPACA_KEY_ID"]
    secret_key = os.environ["ALPACA_SECRET_KEY"]
    anthropic_key = os.environ["ANTHROPIC_API_KEY"]
    model = os.environ.get("CLAUDE_MODEL", "claude-sonnet-5")

    config = load_config()
    base = alpaca_base_url(config["tradingMode"])
    data_base = "https://data.alpaca.markets"

    account = fetch_account(base, key_id, secret_key)
    positions = fetch_positions(base, key_id, secret_key)
    todays_agent_orders = fetch_todays_agent_orders(base, key_id, secret_key)
    all_agent_orders = fetch_all_agent_orders(base, key_id, secret_key)

    watchlist = config.get("watchlist") or []
    symbols = sorted(set(watchlist) | {p["symbol"] for p in positions})
    quotes = {s: fetch_latest_quote(data_base, key_id, secret_key, s) for s in symbols}
    quotes = {k: v for k, v in quotes.items() if v is not None}

    prompt = build_prompt(account, positions, quotes, watchlist)
    raw = call_claude(anthropic_key, model, prompt)
    parsed = parse_agent_response(raw)

    run_log = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "tradingMode": config["tradingMode"],
        "summary": parsed.get("summary", ""),
        "proposals": [],
    }

    print(f"Agent summary: {parsed.get('summary', '')}")

    for proposal in parsed.get("proposals", []):
        action = (proposal.get("action") or "").lower()
        if action not in ("buy", "sell"):
            continue
        eligible, reason = apply_guardrails(proposal, config, account, positions, todays_agent_orders, all_agent_orders)
        entry = {
            "symbol": proposal["symbol"].upper(),
            "action": action,
            "notionalUSD": proposal.get("notionalUSD"),
            "confidence": proposal.get("confidence"),
            "reasoning": proposal.get("reasoning"),
            "status": "blocked",
            "blockReason": reason,
        }
        if eligible:
            if config.get("autoExecuteEnabled"):
                try:
                    order = place_order(base, key_id, secret_key, entry["symbol"], action, entry["notionalUSD"])
                    entry["status"] = "executed"
                    entry["orderId"] = order.get("id")
                    todays_agent_orders.append(order)
                    all_agent_orders.append(order)
                    print(f"EXECUTED: {action} ${entry['notionalUSD']:.0f} {entry['symbol']} (order {order.get('id')})")
                except Exception as e:
                    entry["status"] = "failed"
                    entry["blockReason"] = str(e)
                    print(f"FAILED to execute {entry['symbol']}: {e}")
            else:
                entry["status"] = "approved"
                print(f"APPROVED (auto-execute off, no action taken): {action} ${entry['notionalUSD']:.0f} {entry['symbol']}")
        else:
            print(f"BLOCKED: {action} ${entry.get('notionalUSD')} {entry['symbol']} - {reason}")
        run_log["proposals"].append(entry)

    os.makedirs(os.path.dirname(LOG_PATH), exist_ok=True)
    with open(LOG_PATH, "a") as f:
        f.write(json.dumps(run_log) + "\n")


if __name__ == "__main__":
    try:
        main()
    except urllib.error.HTTPError as e:
        print(f"HTTP error: {e.code} {e.read().decode()}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
