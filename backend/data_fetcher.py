"""Fetch daily OHLCV for the NSE universe via yfinance, with local caching.

Free / $0: uses yfinance (unofficial Yahoo Finance). Good enough to validate
the strategy rules. Swap for Kite/Global Datafeeds for production later.
"""
from __future__ import annotations

import os
import time
import pandas as pd
import yfinance as yf

from symbols import NIFTY_500

DATA_DIR = os.path.join(os.path.dirname(__file__), "data")
CACHE_FILE = os.path.join(DATA_DIR, "ohlcv.parquet")


def _cache_path(period: str) -> str:
    return os.path.join(DATA_DIR, f"ohlcv_{period}.parquet")


def _yahoo_symbol(nse_symbol: str) -> str:
    """NSE symbol -> Yahoo ticker (append .NS)."""
    return f"{nse_symbol.strip().upper()}.NS"


def fetch_all(period: str = "2y",
              symbols: list[str] | None = None,
              use_cache: bool = True,
              batch_size: int = 40,
              pause: float = 1.0) -> dict[str, pd.DataFrame]:
    """Return {nse_symbol: DataFrame[Open,High,Low,Close,Volume]} indexed by date.

    Caches the combined result to parquet so repeat runs are instant/offline.
    """
    os.makedirs(DATA_DIR, exist_ok=True)
    symbols = symbols or NIFTY_500
    cache = _cache_path(period)

    if use_cache and os.path.exists(cache):
        print(f"Loading cached data from {cache}")
        combined = pd.read_parquet(cache)
        return _split_by_symbol(combined)

    frames: list[pd.DataFrame] = []
    yahoo = [_yahoo_symbol(s) for s in symbols]
    y2nse = {_yahoo_symbol(s): s for s in symbols}

    for i in range(0, len(yahoo), batch_size):
        batch = yahoo[i:i + batch_size]
        print(f"Fetching {i + 1}-{i + len(batch)} of {len(yahoo)} ...")
        try:
            data = yf.download(
                tickers=" ".join(batch),
                period=period,
                interval="1d",
                group_by="ticker",
                auto_adjust=False,
                threads=False,  # avoid yfinance SQLite cache 'database is locked'
                progress=False,
            )
        except Exception as e:  # network/rate-limit
            print(f"  batch failed: {e}; retrying once after pause")
            time.sleep(pause * 3)
            try:
                data = yf.download(tickers=" ".join(batch), period=period,
                                   interval="1d", group_by="ticker",
                                   auto_adjust=False, threads=False,
                                   progress=False)
            except Exception as e2:
                print(f"  batch failed again: {e2}; skipping")
                continue

        for yt in batch:
            try:
                df = data[yt] if len(batch) > 1 else data
                df = df[["Open", "High", "Low", "Close", "Volume"]].dropna()
                if df.empty:
                    continue
                df = df.copy()
                df["symbol"] = y2nse[yt]
                frames.append(df)
            except (KeyError, Exception):
                continue
        time.sleep(pause)

    if not frames:
        raise RuntimeError("No data fetched. Check network / yfinance status.")

    combined = pd.concat(frames)
    combined.to_parquet(cache)
    print(f"Cached {combined['symbol'].nunique()} symbols to {cache}")
    return _split_by_symbol(combined)


def _split_by_symbol(combined: pd.DataFrame) -> dict[str, pd.DataFrame]:
    out: dict[str, pd.DataFrame] = {}
    for sym, df in combined.groupby("symbol"):
        d = df.drop(columns=["symbol"]).sort_index()
        out[sym] = d
    return out


if __name__ == "__main__":
    # Quick smoke test on a tiny subset (won't hammer the API).
    test = ["RELIANCE", "TCS", "TATAMOTORS"]
    data = fetch_all(period="1y", symbols=test, use_cache=False)
    for s, df in data.items():
        print(s, df.shape, df.index.min().date(), "->", df.index.max().date())
        print(df.tail(2))
