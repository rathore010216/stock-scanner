"""Lightweight intraday-ish quote refresh (runs every ~30 min in market hours).

Unlike publish.py (full screener + charts, once daily), this only fetches the
LATEST price + previous close for the symbols that matter:
  - symbols currently in /stock/latest matches
  - symbols held in any /portfolios/*/holdings

Writes /stock/quotes/{symbol} = {price, prevClose, ts} and /stock/quotesAsOf.
Fast + few symbols => low yfinance rate-limit risk.

Honest: these are delayed/periodic quotes (yfinance), refreshed ~every 30 min,
NOT real-time ticks. Fine for a swing/paper tool.
"""
from __future__ import annotations

import datetime as dt
import json
import os

import yfinance as yf


def _init_admin():
    db_url = os.environ.get("FIREBASE_DB_URL", "").rstrip("/")
    sa_json = os.environ.get("FIREBASE_SERVICE_ACCOUNT", "")
    if not db_url or not sa_json:
        raise SystemExit("FIREBASE_DB_URL / FIREBASE_SERVICE_ACCOUNT not set")
    import firebase_admin
    from firebase_admin import credentials
    cred = credentials.Certificate(json.loads(sa_json))
    firebase_admin.initialize_app(cred, {"databaseURL": db_url})


def _symbols_to_quote() -> list[str]:
    from firebase_admin import db as admin_db
    syms = set()

    latest = admin_db.reference("stock/latest/matches").get()
    if isinstance(latest, list):
        for m in latest:
            if isinstance(m, dict) and m.get("symbol"):
                syms.add(m["symbol"])

    portfolios = admin_db.reference("portfolios").get()
    if isinstance(portfolios, dict):
        for _uid, pdata in portfolios.items():
            if not isinstance(pdata, dict):
                continue
            holdings = pdata.get("holdings")
            if isinstance(holdings, dict):
                for sym, h in holdings.items():
                    if isinstance(h, dict) and (h.get("qty") or 0) > 0:
                        syms.add(sym)
    return sorted(syms)


def fetch_quotes(symbols: list[str]) -> dict:
    if not symbols:
        return {}
    yahoo = [f"{s}.NS" for s in symbols]
    # 2 days of daily bars gives us latest price + previous close cheaply.
    data = yf.download(
        tickers=" ".join(yahoo),
        period="5d",
        interval="1d",
        group_by="ticker",
        auto_adjust=False,
        threads=False,
        progress=False,
    )
    out = {}
    for s in symbols:
        yt = f"{s}.NS"
        try:
            df = data[yt] if len(yahoo) > 1 else data
            closes = df["Close"].dropna()
            if closes.empty:
                continue
            last = float(closes.iloc[-1])
            prev = float(closes.iloc[-2]) if len(closes) >= 2 else last
            out[s] = {"price": round(last, 2), "prevClose": round(prev, 2)}
        except Exception:
            continue
    return out


def main():
    _init_admin()
    from firebase_admin import db as admin_db

    symbols = _symbols_to_quote()
    print(f"Quoting {len(symbols)} symbols ...")
    quotes = fetch_quotes(symbols)
    if not quotes:
        print("No quotes fetched; skipping write.")
        return
    now = dt.datetime.now(dt.timezone.utc).isoformat()
    for sym, q in quotes.items():
        q["ts"] = now
    admin_db.reference("stock/quotes").update(quotes)
    admin_db.reference("stock/quotesAsOf").set(now)
    print(f"Updated {len(quotes)} quotes at {now}")


if __name__ == "__main__":
    main()
