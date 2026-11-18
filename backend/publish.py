"""Daily publisher: run all screeners + build chart data, push to Firebase RTDB.

Runs in CI (GitHub Actions) after market close. Writes to the shared
family-locator Firebase project under the /stock/ namespace so it never
touches the locator's data.

Output structure in RTDB:
  /stock/latest = {
     as_of, generated_at, disclaimer,
     screeners: [list of screener keys available],
     matches: [ {symbol, price, rsi, triggered:[...], chart:{dates,close,ema50,
                 ema200,bb_upper,bb_lower,volume,vol_avg20,macd,macd_signal,
                 macd_hist,rsi}} ]
  }
  /stock/daily/<date> = same payload (history)

Writes via RTDB REST API using FIREBASE_DB_URL + FIREBASE_DB_SECRET env vars.

Env:
  FIREBASE_DB_URL   e.g. https://stock-scanner-a4418-default-rtdb.firebaseio.com
  FIREBASE_DB_SECRET  a database secret (legacy token) OR omitted if rules allow
"""
from __future__ import annotations

import datetime as dt
import json
import os
import sys

import pandas as pd

import config as C
from data_fetcher import fetch_all
from indicators import compute_indicators
from scoring import passes_universe, DISCLAIMER
import screeners as S

CHART_DAYS = 120
MAX_MATCHES = 200  # cap payload size


def _series(d, col, ndigits=2):
    return [None if pd.isna(v) else round(float(v), ndigits) for v in d[col]]


def _r(v, nd=2):
    return None if v is None or pd.isna(v) else round(float(v), nd)


def build_stats(df: pd.DataFrame) -> dict:
    """Summary numbers for the chart screen, from the FULL history (the chart
    series is only the last CHART_DAYS bars, too short for 1Y / 52-week).

    returns: % change over 1W/1M/3M/6M/1Y (5/21/63/126/252 trading days),
    52-week high/low (from daily High/Low), % below the 52w high, ATR as % of
    price, today's volume vs its 20-day average, ADX, and trend flags.
    """
    close = df["Close"].dropna()
    if close.empty:
        return {}
    last = float(close.iloc[-1])
    rets = {}
    for label, n in (("1W", 5), ("1M", 21), ("3M", 63), ("6M", 126), ("1Y", 252)):
        if len(close) > n and close.iloc[-1 - n] > 0:
            rets[label] = round((last / float(close.iloc[-1 - n]) - 1) * 100, 1)
    yr = df.tail(252)
    hi52, lo52 = yr["High"].max(), yr["Low"].min()
    row = df.iloc[-1]
    vol, vavg = row.get("Volume"), row.get("vol_avg_20")
    ema50, ema200 = row.get("ema_fast"), row.get("ema_slow")
    out = {
        "returns": rets,
        "high52": _r(hi52),
        "low52": _r(lo52),
        "pctFromHigh52": _r((last / hi52 - 1) * 100, 1) if hi52 and hi52 > 0 else None,
        "atrPct": _r(row.get("atr") / last * 100, 2) if last > 0 and not pd.isna(row.get("atr")) else None,
        "volVsAvg": _r(vol / vavg, 2) if vavg and not pd.isna(vavg) and vavg > 0 and not pd.isna(vol) else None,
        "adx": _r(row.get("adx"), 1),
        "aboveEma50": None if pd.isna(ema50) else bool(last > ema50),
        "aboveEma200": None if pd.isna(ema200) else bool(last > ema200),
    }
    return {k: v for k, v in out.items() if v is not None}


def build_chart(df: pd.DataFrame) -> dict:
    d = df.tail(CHART_DAYS)
    return {
        "stats": build_stats(df),
        "dates": [str(ix.date()) for ix in d.index],
        "close": _series(d, "Close"),
        "ema50": _series(d, "ema_fast"),
        "ema200": _series(d, "ema_slow"),
        "bb_upper": _series(d, "bb_upper"),
        "bb_lower": _series(d, "bb_lower"),
        "volume": [None if pd.isna(v) else int(v) for v in d["Volume"]],
        "vol_avg20": _series(d, "vol_avg_20", 0),
        "macd": _series(d, "macd", 3),
        "macd_signal": _series(d, "macd_signal", 3),
        "macd_hist": _series(d, "macd_hist", 3),
        "rsi": _series(d, "rsi", 1),
    }


def build_payload(extra_symbols: set[str] | None = None):
    """Screen the universe. Charts are built for every match AND for
    `extra_symbols` (held / watchlisted stocks), so their chart screens work
    even when they don't match any screener or aren't in the Nifty 500."""
    from symbols import get_universe
    extra = set(extra_symbols or ())
    universe = get_universe()
    data = fetch_all(period="2y", symbols=sorted(set(universe) | extra),
                     use_cache=False)
    ind = {}
    for sym, raw in data.items():
        if len(raw) < C.EMA_SLOW + 5:
            continue
        ind[sym] = compute_indicators(raw)
    # Only universe stocks are screened; extras just get charts.
    universe_set = set(universe)
    screen_ind = {s: d for s, d in ind.items() if s in universe_set}

    momentum_set = S.momentum_top_decile(screen_ind, formation=60, top_frac=0.10)
    momentum_6m_set = S.momentum_6m(screen_ind, top_frac=0.10)
    momentum_12_1_set = S.momentum_12_1(screen_ind, top_frac=0.10)

    matches = []
    charts = {}  # symbol -> chart dict (stored separately, fetched on demand)
    for sym, df in screen_ind.items():
        if not passes_universe(df, df.iloc[-1]):
            continue
        triggered = []
        for key, fn in S.PER_STOCK.items():
            ok, _ = fn(df)
            if ok:
                triggered.append(key)
        if sym in momentum_set:
            triggered.append("momentum")
        if sym in momentum_6m_set:
            triggered.append("momentum_6m")
        if sym in momentum_12_1_set:
            triggered.append("momentum_12_1")
        if not triggered:
            continue
        row = df.iloc[-1]
        matches.append({
            "symbol": sym,
            "price": round(float(row["Close"]), 2),
            "rsi": round(float(row["rsi"]), 1)
            if not pd.isna(row["rsi"]) else None,
            "triggered": triggered,
            "num_triggered": len(triggered),
        })
        charts[sym] = build_chart(df)

    matches.sort(key=lambda m: (-m["num_triggered"], m["symbol"]))
    matches = matches[:MAX_MATCHES]
    kept = {m["symbol"] for m in matches}
    charts = {s: c for s, c in charts.items() if s in kept}
    for sym in extra:
        if sym not in charts and sym in ind:
            charts[sym] = build_chart(ind[sym])

    as_of = None
    if screen_ind:
        as_of = str(max(d.index[-1] for d in screen_ind.values()).date())
    summary = {
        "as_of": as_of,
        "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "disclaimer": DISCLAIMER,
        "screeners": list(S.PER_STOCK.keys())
        + ["momentum", "momentum_6m", "momentum_12_1"],
        "matches": matches,
    }
    return summary, charts


def _init_admin():
    """Initialise the firebase-admin SDK (official server method).

    Auth via the service-account key in FIREBASE_SERVICE_ACCOUNT. Admin SDK
    writes bypass security rules entirely (privileged), so ".write": false is
    fine for clients.
    """
    db_url = os.environ.get("FIREBASE_DB_URL", "").rstrip("/")
    sa_json = os.environ.get("FIREBASE_SERVICE_ACCOUNT", "")
    if not db_url:
        raise SystemExit("FIREBASE_DB_URL not set")
    if not sa_json:
        raise SystemExit("FIREBASE_SERVICE_ACCOUNT not set")

    import firebase_admin
    from firebase_admin import credentials

    cred = credentials.Certificate(json.loads(sa_json))
    firebase_admin.initialize_app(cred, {"databaseURL": db_url})


def portfolio_symbols() -> set[str]:
    """Symbols held (qty > 0) or watchlisted in any /portfolios/{uid}."""
    from firebase_admin import db as admin_db
    out: set[str] = set()
    portfolios = admin_db.reference("portfolios").get()
    if isinstance(portfolios, dict):
        for p in portfolios.values():
            if not isinstance(p, dict):
                continue
            for sym, h in (p.get("holdings") or {}).items():
                if isinstance(h, dict) and (h.get("qty") or 0) > 0:
                    out.add(str(sym).upper())
            out.update(str(s).upper() for s in (p.get("watchlist") or {}))
    return out


def publish(summary: dict, charts: dict):
    """Write the scan to RTDB. Requires _init_admin() first."""
    from firebase_admin import db as admin_db

    as_of = summary["as_of"] or "unknown"
    admin_db.reference("stock/latest").set(summary)
    admin_db.reference(f"stock/daily/{as_of}").set(summary)
    admin_db.reference("stock/charts").set(charts)
    print(f"Published summary ({len(summary['matches'])} matches) + "
          f"{len(charts)} charts for {as_of}")


def main():
    dry = "--dry-run" in sys.argv
    extra: set[str] = set()
    if not dry:
        _init_admin()
        try:
            extra = portfolio_symbols()
            print(f"Also charting {len(extra)} held/watchlisted symbols")
        except Exception as e:
            print(f"Could not read portfolios (charts for matches only): {e}")
    summary, charts = build_payload(extra)
    print(f"Built: {len(summary['matches'])} matches, {len(charts)} charts, "
          f"as_of {summary['as_of']}")
    if dry:
        with open("payload_preview.json", "w") as f:
            json.dump({"summary": summary, "charts_count": len(charts)}, f,
                      indent=2)
        with open("charts_preview.json", "w") as f:
            json.dump(charts, f)
        print("Dry run: wrote payload_preview.json + charts_preview.json")
        return
    publish(summary, charts)


if __name__ == "__main__":
    main()
