"""Server-side auto-exit for the paper-trading portfolios.

After quotes.py refreshes /stock/quotes, this evaluates every holding in every
/portfolios/{uid} against the fresh price and, if the stop-loss or target is
hit, executes a FULL-QTY paper sell — writing exactly what the Flutter
`PortfolioService.sell()` would write, so an auto-exit is indistinguishable
from a manual sell (plus a `reason` tag).

Trigger rules (match Dart Holding helpers):
  stopHit(price):   stopLoss != None and price <= stopLoss
  targetHit(price): target  != None and price >= target
If BOTH are hit on the same quote, STOP takes priority (pessimistic), matching
the backtester's convention.

Fill price: the triggering quote price (market-style fill), matching how a
real market stop/target would approximately behave. Realized P/L and fees use
backend/fees.py, a byte-for-byte port of the Dart Fees model.

Writes per executed exit (mirrors Dart sell()):
  portfolios/{uid}/cash         = cash + (proceeds - sellFee)
  portfolios/{uid}/realizedPnl  = prev + ((price - avgPrice)*qty - sellFee)
  portfolios/{uid}/holdings/{sym} = removed (full-qty exit)
  portfolios/{uid}/trades/{push} = {symbol, side:'sell', qty, price,
                                     realizedPnl, fee, ms, reason}

Concurrency: each portfolio is updated inside a transaction on
portfolios/{uid} so a simultaneous manual trade from the app can't be clobbered.
"""
from __future__ import annotations

import datetime as dt

from fees import fee_for_trade

START_CAPITAL = 100000.0


def _evaluate_holding(sym: str, h: dict, price: float):
    """Return (reason, 'auto-sl'|'auto-target') if an exit should fire, else None.

    Mirrors Dart Holding.stopHit / targetHit. Stop takes priority.
    """
    if not isinstance(h, dict):
        return None
    qty = h.get("qty") or 0
    if qty <= 0:
        return None
    stop = h.get("stopLoss")
    target = h.get("target")
    stop_hit = isinstance(stop, (int, float)) and price <= stop
    target_hit = isinstance(target, (int, float)) and price >= target
    if stop_hit:
        return "auto-sl"
    if target_hit:
        return "auto-target"
    return None


def _apply_exits_txn(current, quotes: dict, now_ms: int, now_iso: str,
                     planned_out: list):
    """Transaction function on portfolios/{uid}.

    Pure w.r.t. `current` (the current portfolio dict); returns the new dict.
    Appends human-readable records to `planned_out` for logging/dry-run.
    NOTE: Firebase may call this multiple times; keep it idempotent and derive
    everything from `current`.
    """
    if not isinstance(current, dict):
        return current

    holdings = current.get("holdings")
    if not isinstance(holdings, dict):
        return current  # nothing to do

    cash = current.get("cash")
    cash = float(cash) if isinstance(cash, (int, float)) else START_CAPITAL
    realized_total = current.get("realizedPnl")
    realized_total = (float(realized_total)
                      if isinstance(realized_total, (int, float)) else 0.0)

    trades = current.get("trades")
    if not isinstance(trades, dict):
        trades = {}

    changed = False
    # Iterate over a snapshot of items so we can mutate holdings safely.
    for sym, h in list(holdings.items()):
        price = quotes.get(sym)
        if not isinstance(price, (int, float)):
            continue
        reason = _evaluate_holding(sym, h, float(price))
        if reason is None:
            continue

        qty = int(h.get("qty") or 0)
        avg = float(h.get("avgPrice") or 0.0)
        proceeds = qty * price
        fee = fee_for_trade(is_buy=False, turnover=proceeds)
        net_proceeds = proceeds - fee
        realized = (price - avg) * qty - fee  # net of sell-side fee

        cash += net_proceeds
        realized_total += realized

        # Full-qty exit => remove the holding entirely.
        del holdings[sym]

        # Push a trade with a client-push-style key. Using a timestamp-based
        # key keeps it deterministic across transaction retries for the same
        # symbol so we never double-insert.
        trade_key = f"auto_{sym}_{now_ms}"
        trades[trade_key] = {
            "symbol": sym,
            "side": "sell",
            "qty": qty,
            "price": round(float(price), 2),
            "realizedPnl": round(float(realized), 2),
            "fee": round(float(fee), 2),
            "ms": now_ms,
            "reason": reason,
        }
        changed = True
        planned_out.append(
            f"  {reason.upper():11s} {sym:14s} qty {qty} @ Rs{price:.2f}  "
            f"fee Rs{fee:.2f}  realized {realized:+.2f}")

    if not changed:
        return current  # abort the transaction (no write)

    current["cash"] = cash
    current["realizedPnl"] = realized_total
    current["holdings"] = holdings
    current["trades"] = trades
    return current


def run_auto_exits(quotes: dict, dry_run: bool = False) -> int:
    """Evaluate all portfolios against `quotes` ({symbol: price}) and execute
    SL/target exits. Returns the number of exits performed. Requires
    firebase_admin to be initialized by the caller (quotes.py does this).
    """
    from firebase_admin import db as admin_db

    now = dt.datetime.now(dt.timezone.utc)
    now_ms = int(now.timestamp() * 1000)
    now_iso = now.isoformat()

    portfolios = admin_db.reference("portfolios").get()
    if not isinstance(portfolios, dict):
        return 0

    total_exits = 0
    for uid, pdata in portfolios.items():
        if not isinstance(pdata, dict):
            continue
        holdings = pdata.get("holdings")
        if not isinstance(holdings, dict) or not holdings:
            continue

        # Quick pre-check so we only touch portfolios that actually have a
        # triggered level (avoids needless transactions).
        pending = []
        for sym, h in holdings.items():
            price = quotes.get(sym)
            if isinstance(price, (int, float)) and \
                    _evaluate_holding(sym, h, float(price)):
                pending.append(sym)
        if not pending:
            continue

        planned: list[str] = []

        if dry_run:
            # Simulate without writing.
            import copy
            _apply_exits_txn(copy.deepcopy(pdata), quotes, now_ms, now_iso,
                             planned)
            if planned:
                print(f"[dry-run] portfolio {uid}:")
                for line in planned:
                    print(line)
                total_exits += len(planned)
            continue

        ref = admin_db.reference(f"portfolios/{uid}")

        def _txn(current):
            # planned is reset each retry to avoid duplicate log lines.
            planned.clear()
            return _apply_exits_txn(current, quotes, now_ms, now_iso, planned)

        ref.transaction(_txn)
        if planned:
            print(f"Auto-exits for portfolio {uid}:")
            for line in planned:
                print(line)
            total_exits += len(planned)

    return total_exits


if __name__ == "__main__":
    # Offline unit check of the exit-decision + accounting math (no Firebase).
    sample_portfolio = {
        "cash": 50000.0,
        "realizedPnl": 0.0,
        "holdings": {
            "AAA": {"qty": 10, "avgPrice": 100.0, "stopLoss": 95.0,
                    "target": 120.0, "firstBuyMs": 1},
            "BBB": {"qty": 5, "avgPrice": 200.0, "stopLoss": 180.0,
                    "target": 210.0, "firstBuyMs": 1},
            "CCC": {"qty": 8, "avgPrice": 50.0, "stopLoss": 40.0,
                    "target": 60.0, "firstBuyMs": 1},
        },
    }
    quotes = {
        "AAA": 94.0,    # stop hit (<=95)
        "BBB": 215.0,   # target hit (>=210)
        "CCC": 52.0,    # neither -> no exit
    }
    planned: list[str] = []
    import copy
    result = _apply_exits_txn(copy.deepcopy(sample_portfolio), quotes,
                              now_ms=1700000000000, now_iso="2026-01-01T00:00:00",
                              planned_out=planned)
    print("Planned exits:")
    for line in planned:
        print(line)
    print("\nResulting holdings:", sorted(result["holdings"].keys()),
          "(expect ['CCC'])")
    print(f"Cash: {result['cash']:.2f}  realizedPnl: {result['realizedPnl']:.2f}")
    print(f"Trades written: {len(result['trades'])}  (expect 2)")
    for k, v in result["trades"].items():
        print(" ", k, v)
