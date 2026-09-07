"""Independent, toggleable screeners — one detector per strategy.

Each function evaluates the LATEST bar of a single stock's indicator DataFrame
and returns (triggered: bool, detail: str) or for momentum a precomputed set.

IMPORTANT (honesty): backtesting showed none of these reliably beat buy-and-hold
after costs. They are RESEARCH FILTERS to help you scan manually, NOT buy
signals. You decide.
"""
from __future__ import annotations

import numpy as np
import pandas as pd

import config as C
from indicators import compute_indicators
from cup_handle import detect_cup_handle

EMA_FAST, EMA_SLOW = 50, 200


def _last(df, col):
    return df[col].iloc[-1]


# ---- Per-stock latest-bar detectors ----

def scr_trend_uptrend(df) -> tuple[bool, str]:
    row = df.iloc[-1]
    ok = (not pd.isna(row["ema_fast"]) and not pd.isna(row["ema_slow"])
          and row["Close"] > row["ema_fast"] > row["ema_slow"])
    return ok, "Close>EMA50>EMA200" if ok else ""


def scr_breakout_52w(df) -> tuple[bool, str]:
    close = df["Close"]
    high = df["High"]
    hh = high.rolling(252).max().shift(1)
    sma200 = close.rolling(EMA_SLOW).mean()
    if len(df) < 260 or pd.isna(hh.iloc[-1]):
        return False, ""
    ok = close.iloc[-1] > hh.iloc[-1] and close.iloc[-1] > sma200.iloc[-1]
    return ok, "new 52w high" if ok else ""


def scr_rsi2_oversold(df) -> tuple[bool, str]:
    close = df["Close"]
    sma200 = close.rolling(EMA_SLOW).mean()
    # RSI(2)
    delta = close.diff()
    gain = delta.clip(lower=0).ewm(alpha=0.5, adjust=False).mean()
    loss = (-delta.clip(upper=0)).ewm(alpha=0.5, adjust=False).mean()
    rs = gain / loss.replace(0, np.nan)
    rsi2 = (100 - 100 / (1 + rs)).fillna(100)
    if len(df) < EMA_SLOW + 5:
        return False, ""
    ok = close.iloc[-1] > sma200.iloc[-1] and rsi2.iloc[-1] < 10
    return ok, f"RSI2 {rsi2.iloc[-1]:.0f} (oversold in uptrend)" if ok else ""


def scr_volume_surge(df) -> tuple[bool, str]:
    row = df.iloc[-1]
    close = df["Close"]
    avg20 = df["Volume"].rolling(20).mean()
    sma200 = close.rolling(EMA_SLOW).mean()
    day_ret = close.pct_change().iloc[-1]
    if pd.isna(avg20.iloc[-1]) or avg20.iloc[-1] <= 0 or pd.isna(sma200.iloc[-1]):
        return False, ""
    mult = row["Volume"] / avg20.iloc[-1]
    ok = mult >= 3.0 and day_ret >= 0.02 and row["Close"] > sma200.iloc[-1]
    return ok, f"vol {mult:.1f}x avg, +{day_ret*100:.1f}%" if ok else ""


def scr_bollinger_squeeze(df) -> tuple[bool, str]:
    if len(df) < 40:
        return False, ""
    bw = df["bb_bandwidth"]
    bw_min = df["bb_bw_min_6mo"]
    if pd.isna(bw.iloc[-1]) or pd.isna(bw_min.iloc[-1]):
        return False, ""
    prev = bw.iloc[-2]
    ok = (bw.iloc[-1] > bw_min.iloc[-1] * 1.1
          and not pd.isna(prev) and prev <= bw_min.iloc[-1] * 1.05)
    return ok, "squeeze release" if ok else ""


def scr_macd_cross(df) -> tuple[bool, str]:
    if len(df) < 40:
        return False, ""
    for j in range(len(df) - 3, len(df)):
        if j < 1:
            continue
        prev = df["macd"].iloc[j - 1] - df["macd_signal"].iloc[j - 1]
        curr = df["macd"].iloc[j] - df["macd_signal"].iloc[j]
        if prev <= 0 and curr > 0:
            return True, "MACD cross up"
    return False, ""


def scr_cup_handle(df) -> tuple[bool, str]:
    det = detect_cup_handle(df, require_breakout=False)
    if det:
        tag = "cup&handle" + (" (breakout)" if det["breakout"] else " (forming)")
        return True, f"{tag}, depth {det['depth_pct']}%"
    return False, ""


# Per-stock screeners registry.
PER_STOCK = {
    "trend": scr_trend_uptrend,
    "breakout_52w": scr_breakout_52w,
    "rsi2": scr_rsi2_oversold,
    "volume_surge": scr_volume_surge,
    "bollinger_squeeze": scr_bollinger_squeeze,
    "macd_cross": scr_macd_cross,
    "cup_handle": scr_cup_handle,
}


# ---- Cross-sectional momentum (needs the whole universe) ----

def momentum_top_decile(data_ind: dict[str, pd.DataFrame],
                        formation: int = 60, top_frac: float = 0.10) -> set[str]:
    """Return the set of symbols in the top decile by `formation`-day return,
    filtered to those above their 200-DMA, evaluated on the latest common bar."""
    rs = {}
    for sym, df in data_ind.items():
        if len(df) < formation + EMA_SLOW:
            continue
        close = df["Close"]
        sma200 = close.rolling(EMA_SLOW).mean().iloc[-1]
        if pd.isna(sma200) or close.iloc[-1] <= sma200:
            continue
        past = close.iloc[-1]
        older = close.iloc[-1 - formation]
        if older > 0:
            rs[sym] = (past - older) / older
    if not rs:
        return set()
    ranked = sorted(rs.items(), key=lambda kv: kv[1], reverse=True)
    n_top = max(1, int(len(ranked) * top_frac))
    return {s for s, _ in ranked[:n_top]}
