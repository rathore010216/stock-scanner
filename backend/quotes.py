"""Lightweight intraday quote refresh.

Unlike publish.py (full screener + charts, once daily), this only fetches the
LATEST price + previous close for the symbols that matter:
  - symbols currently in /stock/latest matches
  - symbols held in any /portfolios/*/holdings

Writes /stock/quotes/{symbol} = {price, prevClose, ts} and /stock/quotesAsOf,
then runs the server-side SL/target auto-exit.

Modes:
  python quotes.py              one refresh cycle (original behaviour)
  python quotes.py --loop       repeat every --interval seconds (default 120)
                                until --until-utc (default 10:05 UTC = 15:35
                                IST) or --max-minutes elapses, whichever is
                                first. Always runs at least one cycle. Backs
                                off on Yahoo/Firebase errors and stops early
                                on NSE holidays.
  --dry-run                     don't execute auto-exits, just print them.

Honest: these are delayed/periodic quotes (yfinance), NOT real-time ticks.
Fine for a swing/paper tool.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import sys
import time

import yfinance as yf

IST = dt.timezone(dt.timedelta(hours=5, minutes=30))


def _init_admin():
    db_url = os.environ.get("FIREBASE_DB_URL", "").rstrip("/")
    sa_json = os.environ.get("FIREBASE_SERVICE_ACCOUNT", "")
    if not db_url or not sa_json:
        raise SystemExit("FIREBASE_DB_URL / FIREBASE_SERVICE_ACCOUNT not set")
    import firebase_admin
    from firebase_admin import credentials
    cred = credentials.Certificate(json.loads(sa_json))
    firebase_admin.initialize_app(cred, {"databaseURL": db_url})


def _symbols_to_quote(portfolios) -> list[str]:
    from firebase_admin import db as admin_db
    syms = set()

    latest = admin_db.reference("stock/latest/matches").get()
    if isinstance(latest, list):
        for m in latest:
            if isinstance(m, dict) and m.get("symbol"):
                syms.add(m["symbol"])

    if isinstance(portfolios, dict):
        for _uid, pdata in portfolios.items():
            if not isinstance(pdata, dict):
                continue
            holdings = pdata.get("holdings")
            if isinstance(holdings, dict):
                for sym, h in holdings.items():
                    if isinstance(h, dict) and (h.get("qty") or 0) > 0:
                        syms.add(sym)
            # Watchlist symbols too, so the app's watchlist gets live prices.
            watchlist = pdata.get("watchlist")
            if isinstance(watchlist, dict):
                syms.update(str(s) for s in watchlist.keys())
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


def fetch_indices() -> tuple[dict, dt.date | None]:
    """Fetch NIFTY 50 and SENSEX latest + previous close for the header strip.

    Uses Yahoo index tickers. Cheap (2 tickers). Returns
    ({name: {price, prevClose}}, date of NIFTY's latest daily bar). The bar
    date lets the loop detect a market holiday (no bar for today).
    """
    tickers = {"NIFTY": "^NSEI", "SENSEX": "^BSESN"}
    try:
        data = yf.download(
            tickers=" ".join(tickers.values()),
            period="5d",
            interval="1d",
            group_by="ticker",
            auto_adjust=False,
            threads=False,
            progress=False,
        )
    except Exception as e:
        print(f"  index fetch failed: {e}")
        return {}, None
    out = {}
    last_date = None
    for name, yt in tickers.items():
        try:
            df = data[yt]
            closes = df["Close"].dropna()
            if closes.empty:
                continue
            last = float(closes.iloc[-1])
            prev = float(closes.iloc[-2]) if len(closes) >= 2 else last
            out[name] = {"price": round(last, 2), "prevClose": round(prev, 2)}
            if name == "NIFTY":
                last_date = closes.index[-1].date()
        except Exception:
            continue
    return out, last_date


def run_cycle(dry_run: bool = False) -> tuple[int, dt.date | None]:
    """One refresh: indices + quotes + auto-exit.

    Returns (number of quotes written, NIFTY latest bar date or None).
    Raises on Firebase errors so the loop can back off.
    """
    from firebase_admin import db as admin_db

    now = dt.datetime.now(dt.timezone.utc).isoformat()

    # Index strip (NIFTY / SENSEX) — cheap, always fetch.
    indices, idx_date = fetch_indices()
    if indices:
        for _n, q in indices.items():
            q["ts"] = now
        admin_db.reference("stock/indices").set(indices)
        print(f"Updated indices: {list(indices.keys())}")

    # One read of /portfolios per cycle, shared by symbol discovery and the
    # auto-exit pre-check (the exit itself re-reads inside a transaction).
    portfolios = admin_db.reference("portfolios").get()
    symbols = _symbols_to_quote(portfolios)
    print(f"Quoting {len(symbols)} symbols ...")
    quotes = fetch_quotes(symbols)
    if not quotes:
        print("No quotes fetched; skipping quotes write.")
        return 0, idx_date
    for sym, q in quotes.items():
        q["ts"] = now
    admin_db.reference("stock/quotes").update(quotes)
    admin_db.reference("stock/quotesAsOf").set(now)
    print(f"Updated {len(quotes)} quotes at {now}")

    # ---- Server-side auto-exit on stop-loss / target --------------------
    # Right after fresh quotes are written, evaluate every paper holding and
    # auto-sell (full qty) any position whose SL or target was hit. Uses the
    # just-fetched prices so it fires even when the app is closed.
    from auto_exit import run_auto_exits
    price_map = {sym: q["price"] for sym, q in quotes.items()
                 if isinstance(q.get("price"), (int, float))}
    try:
        n = run_auto_exits(price_map, dry_run=dry_run, portfolios=portfolios)
        if n:
            print(f"Auto-exit: {n} paper position(s) "
                  f"{'would be' if dry_run else ''} closed on SL/target.")
        else:
            print("Auto-exit: no SL/target triggers this cycle.")
    except Exception as e:
        # Never let an auto-exit error break the quotes job.
        print(f"Auto-exit error (quotes still updated): {e}")

    # ---- Financials for the chart screen's Financials tab ----------------
    # A few missing/week-old symbols per cycle (cheap index read). Never let
    # it break the quotes job.
    try:
        from fundamentals import refresh_fundamentals
        refresh_fundamentals(symbols)
    except Exception as e:
        print(f"Fundamentals error (quotes still updated): {e}")
    return len(quotes), idx_date


def _parse_args(argv):
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawTextHelpFormatter)
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--loop", action="store_true")
    p.add_argument("--interval", type=int,
                   default=int(os.environ.get("QUOTES_INTERVAL_SEC", "120")),
                   help="seconds between cycle starts in --loop (default 120)")
    p.add_argument("--until-utc", default="10:05",
                   help="stop looping at this UTC HH:MM (default 10:05 = "
                        "15:35 IST)")
    p.add_argument("--max-minutes", type=int, default=345,
                   help="hard cap on loop duration (default 345; GitHub "
                        "jobs are killed at 360)")
    return p.parse_args(argv)


def main(argv=None):
    args = _parse_args(sys.argv[1:] if argv is None else argv)
    _init_admin()

    if not args.loop:
        run_cycle(dry_run=args.dry_run)
        return

    start = dt.datetime.now(dt.timezone.utc)
    hh, mm = (int(x) for x in args.until_utc.split(":"))
    until = start.replace(hour=hh, minute=mm, second=0, microsecond=0)
    deadline = min(until, start + dt.timedelta(minutes=args.max_minutes))
    interval = max(30, args.interval)  # be polite to Yahoo
    print(f"Loop mode: every {interval}s until {deadline.isoformat()}")

    failures = 0
    cycle = 0
    while True:
        cycle += 1
        t0 = time.monotonic()
        print(f"\n--- cycle {cycle} @ "
              f"{dt.datetime.now(IST).strftime('%H:%M:%S')} IST ---")
        ok = False
        idx_date = None
        try:
            n, idx_date = run_cycle(dry_run=args.dry_run)
            ok = n > 0
        except Exception as e:
            print(f"Cycle error: {e}")

        # Holiday guard: once well past the open, if NIFTY still has no bar
        # for today, the market is closed today -> stop wasting cycles.
        now_ist = dt.datetime.now(IST)
        if (idx_date is not None
                and now_ist.time() >= dt.time(10, 0)
                and idx_date < now_ist.date()):
            print(f"No NIFTY bar for {now_ist.date()} (latest {idx_date}); "
                  "market closed today. Exiting loop.")
            return

        if ok:
            failures = 0
            wait = interval - (time.monotonic() - t0)
        else:
            # Exponential back-off on errors / empty fetches (rate limits),
            # capped at 15 min.
            failures += 1
            wait = min(interval * (2 ** failures), 900)
            print(f"Backing off {wait:.0f}s (failure #{failures})")

        wake = dt.datetime.now(dt.timezone.utc) + dt.timedelta(
            seconds=max(0, wait))
        if wake >= deadline:
            print("Deadline reached; exiting loop.")
            return
        time.sleep(max(0, wait))


if __name__ == "__main__":
    main()
