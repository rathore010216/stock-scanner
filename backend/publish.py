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
  FIREBASE_DB_URL   e.g. https://family-locator-a5106-default-rtdb.firebaseio.com
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


def build_chart(df: pd.DataFrame) -> dict:
    d = df.tail(CHART_DAYS)
    return {
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


def build_payload():
    data = fetch_all(period="2y", use_cache=False)
    ind = {}
    for sym, raw in data.items():
        if len(raw) < C.EMA_SLOW + 5:
            continue
        ind[sym] = compute_indicators(raw)

    momentum_set = S.momentum_top_decile(ind, formation=60, top_frac=0.10)
    momentum_6m_set = S.momentum_6m(ind, top_frac=0.10)
    momentum_12_1_set = S.momentum_12_1(ind, top_frac=0.10)

    matches = []
    charts = {}  # symbol -> chart dict (stored separately, fetched on demand)
    for sym, df in ind.items():
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

    as_of = None
    if ind:
        as_of = str(next(iter(ind.values())).index[-1].date())
    summary = {
        "as_of": as_of,
        "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "disclaimer": DISCLAIMER,
        "screeners": list(S.PER_STOCK.keys())
        + ["momentum", "momentum_6m", "momentum_12_1"],
        "matches": matches,
    }
    return summary, charts


def publish(summary: dict, charts: dict):
    """Write to RTDB using the firebase-admin SDK (official server method).

    Auth via the service-account key in FIREBASE_SERVICE_ACCOUNT. The SDK
    handles tokens/scopes correctly, avoiding REST 401 pitfalls. Admin SDK
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
    from firebase_admin import credentials, db as admin_db

    cred = credentials.Certificate(json.loads(sa_json))
    firebase_admin.initialize_app(cred, {"databaseURL": db_url})

    as_of = summary["as_of"] or "unknown"
    admin_db.reference("stock/latest").set(summary)
    admin_db.reference(f"stock/daily/{as_of}").set(summary)
    admin_db.reference("stock/charts").set(charts)
    print(f"Published summary ({len(summary['matches'])} matches) + "
          f"{len(charts)} charts for {as_of}")


def main():
    summary, charts = build_payload()
    print(f"Built: {len(summary['matches'])} matches, {len(charts)} charts, "
          f"as_of {summary['as_of']}")
    if "--dry-run" in sys.argv:
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
