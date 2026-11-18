"""Per-stock financials (P&L + key ratios) from Yahoo, published to Firebase.

Writes:
  /stock/fundamentals/{symbol}   = {name, sector, industry, ratios..., quarterly[],
                                    annual[], ts}
  /stock/fundamentalsAsOf/{symbol} = ISO timestamp (small index, so callers can
                                    find stale entries without reading every
                                    full record)

Units: statement figures (revenue, net profit, operating profit) are in
Rs crore; ratios that Yahoo gives as fractions are converted to percent.
Fundamentals change quarterly, so each symbol is refreshed at most weekly.

Note: Yahoo's per-quarter EPS for NSE stocks is unreliable (0s), so only
trailing EPS from `info` is published. Some quarters can be missing.
"""
from __future__ import annotations

import datetime as dt
import math

import yfinance as yf

CRORE = 1e7
MAX_AGE_DAYS = 7


def _num(v, scale: float = 1.0, nd: int = 2):
    """Float rounded, or None for missing/NaN/inf/non-numeric."""
    try:
        f = float(v)
    except (TypeError, ValueError):
        return None
    if math.isnan(f) or math.isinf(f):
        return None
    return round(f * scale, nd)


def _statement_rows(df, rows: dict, limit: int, label) -> list[dict]:
    """Income statement DataFrame -> list of {period, <key>: value} oldest-first."""
    if df is None or getattr(df, "empty", True):
        return []
    out = []
    for col in list(df.columns)[:limit]:
        rec = {"period": label(col)}
        for key, row in rows.items():
            rec[key] = _num(df.at[row, col], 1 / CRORE, 1) if row in df.index else None
        if any(rec[k] is not None for k in rows):
            out.append(rec)
    return list(reversed(out))


def _q_label(ts) -> str:      # 2026-09-30 -> "Sep 26"
    return ts.strftime("%b %y")


def _fy_label(ts) -> str:     # 2026-03-31 -> "FY26" (Indian FY ends March)
    year = ts.year if ts.month <= 3 else ts.year + 1
    return f"FY{year % 100:02d}"


def fetch_fundamentals(symbol: str) -> dict | None:
    t = yf.Ticker(f"{symbol}.NS")
    info = t.info or {}
    if not info.get("longName") and not info.get("shortName"):
        return None
    pct = lambda k: _num(info.get(k), 100, 1)   # fraction -> %
    rec = {
        "name": info.get("longName") or info.get("shortName"),
        "sector": info.get("sector"),
        "industry": info.get("industry"),
        "marketCapCr": _num(info.get("marketCap"), 1 / CRORE, 0),
        "pe": _num(info.get("trailingPE"), 1, 1),
        "pb": _num(info.get("priceToBook"), 1, 2),
        "eps": _num(info.get("trailingEps")),
        "bookValue": _num(info.get("bookValue")),
        # yfinance already returns dividendYield in percent (e.g. 0.46 = 0.46%).
        "divYield": _num(info.get("dividendYield"), 1, 2),
        "roe": pct("returnOnEquity"),
        "profitMargin": pct("profitMargins"),
        "opMargin": pct("operatingMargins"),
        # Yahoo gives D/E as a percentage (44.3 = 0.44x); publish as a ratio.
        "debtToEquity": _num(info.get("debtToEquity"), 0.01, 2),
        "revenueGrowth": pct("revenueGrowth"),
        "earningsGrowth": pct("earningsGrowth"),
        "high52": _num(info.get("fiftyTwoWeekHigh")),
        "low52": _num(info.get("fiftyTwoWeekLow")),
        "revenueTtmCr": _num(info.get("totalRevenue"), 1 / CRORE, 0),
        "netIncomeTtmCr": _num(info.get("netIncomeToCommon"), 1 / CRORE, 0),
    }
    rows = {"revenue": "Total Revenue", "netProfit": "Net Income",
            "opProfit": "Operating Income"}
    try:
        rec["quarterly"] = _statement_rows(t.quarterly_income_stmt, rows, 6, _q_label)
    except Exception as e:
        print(f"  {symbol}: quarterly statement failed: {e}")
        rec["quarterly"] = []
    try:
        rec["annual"] = _statement_rows(t.income_stmt, rows, 4, _fy_label)
    except Exception as e:
        print(f"  {symbol}: annual statement failed: {e}")
        rec["annual"] = []
    # Drop missing values to keep records small (the app treats absent = n/a).
    rec = {k: v for k, v in rec.items() if v is not None}
    rec["quarterly"] = [{k: v for k, v in q.items() if v is not None} for q in rec["quarterly"]]
    rec["annual"] = [{k: v for k, v in a.items() if v is not None} for a in rec["annual"]]
    return rec


def refresh_fundamentals(symbols: list[str], max_fetch: int = 8,
                         max_age_days: int = MAX_AGE_DAYS) -> int:
    """Fetch fundamentals for up to `max_fetch` symbols that are missing or older
    than `max_age_days`. Returns how many were written. Requires firebase_admin
    to be initialised by the caller."""
    from firebase_admin import db as admin_db

    asof = admin_db.reference("stock/fundamentalsAsOf").get() or {}
    now = dt.datetime.now(dt.timezone.utc)
    cutoff = now - dt.timedelta(days=max_age_days)

    def stale(sym):
        try:
            return dt.datetime.fromisoformat(str(asof.get(sym))) < cutoff
        except (TypeError, ValueError):
            return True  # missing / unparsable

    todo = [s for s in symbols if stale(s)][:max_fetch]
    written = 0
    for sym in todo:
        try:
            rec = fetch_fundamentals(sym)
        except Exception as e:
            print(f"  fundamentals {sym} failed: {e}")
            continue
        ts = now.isoformat()
        if rec is None:
            # Unknown to Yahoo: still stamp it so we don't retry every cycle.
            admin_db.reference(f"stock/fundamentalsAsOf/{sym}").set(ts)
            continue
        rec["ts"] = ts
        admin_db.reference(f"stock/fundamentals/{sym}").set(rec)
        admin_db.reference(f"stock/fundamentalsAsOf/{sym}").set(ts)
        written += 1
    if todo:
        print(f"Fundamentals: refreshed {written}/{len(todo)} "
              f"({len([s for s in symbols if stale(s)]) - len(todo)} still pending)")
    return written


if __name__ == "__main__":
    # Offline-ish check: print one record (no Firebase).
    import json
    import sys
    print(json.dumps(fetch_fundamentals(sys.argv[1] if len(sys.argv) > 1 else "RELIANCE"),
                     indent=1))
