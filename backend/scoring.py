"""Stage-1 trend filter, Stage-2 scoring, universe filters, and pick building.

Produces per-stock result dicts shaped for the 'Today's picks' card UI:
entry, stop, target, R:R, %-to-stop, %-to-target, score, signals, rsi, as-of.
All computations use only data up to the evaluation row (no look-ahead).
"""
from __future__ import annotations

import pandas as pd

import config as C
from indicators import compute_indicators


DISCLAIMER = "Suggestions only - not investment advice. For research use."


def passes_universe(df: pd.DataFrame, row) -> bool:
    """Liquidity / price universe filters (Section 2.3)."""
    if row["Close"] < C.MIN_PRICE:
        return False
    if pd.isna(row["vol_avg_20"]) or row["vol_avg_20"] < C.MIN_AVG_VOLUME_20:
        return False
    return True


def stage1_trend_ok(row) -> bool:
    """Close > EMA50 > EMA200."""
    if pd.isna(row["ema_fast"]) or pd.isna(row["ema_slow"]):
        return False
    return row["Close"] > row["ema_fast"] > row["ema_slow"]


def macd_crossed_up(df: pd.DataFrame, i: int, lookback: int) -> bool:
    """True if MACD crossed above signal within the last `lookback` bars up to i."""
    start = max(1, i - lookback + 1)
    for j in range(start, i + 1):
        prev_diff = df["macd"].iloc[j - 1] - df["macd_signal"].iloc[j - 1]
        curr_diff = df["macd"].iloc[j] - df["macd_signal"].iloc[j]
        if prev_diff <= 0 and curr_diff > 0:
            return True
    return False


def score_row(df: pd.DataFrame, i: int) -> tuple[int, list[str]]:
    """Stage-2 score (0-100) + list of triggered signal names for row i."""
    row = df.iloc[i]
    score = 0
    signals: list[str] = []

    # Breakout (0-30)
    if not pd.isna(row["high_20_prev"]) and row["Close"] > row["high_20_prev"]:
        if not pd.isna(row["vol_avg_20"]) and \
                row["Volume"] > C.VOLUME_SURGE_MULT * row["vol_avg_20"]:
            score += C.SCORE["breakout_with_volume"]
            signals.append("breakout + volume")
        else:
            score += C.SCORE["breakout_only"]
            signals.append("breakout")

    # Bollinger squeeze -> release (0-20)
    bw = row["bb_bandwidth"]
    bw_min = row["bb_bw_min_6mo"]
    if i >= 1 and not pd.isna(bw) and not pd.isna(bw_min):
        bw_prev = df["bb_bandwidth"].iloc[i - 1]
        if bw > bw_min * 1.1 and (not pd.isna(bw_prev) and
                                  bw_prev <= bw_min * 1.05):
            score += C.SCORE["bb_squeeze_release"]
            signals.append("squeeze release")

    # RSI positioning (0-20)
    rsi = row["rsi"]
    if not pd.isna(rsi):
        if 40 <= rsi <= 60:
            score += C.SCORE["rsi_sweet_spot"]
        elif 60 < rsi <= 70:
            score += C.SCORE["rsi_ok"]

    # MACD crossover (0-20)
    if macd_crossed_up(df, i, C.MACD_CROSS_LOOKBACK):
        score += C.SCORE["macd_cross_recent"]
        signals.append("macd cross")

    # Volume confirmation (0-10)
    if not pd.isna(row["vol_avg_20"]) and row["Volume"] > row["vol_avg_20"]:
        score += C.SCORE["volume_confirm"]
        signals.append("volume above avg")

    return score, signals


def build_pick(symbol: str, df: pd.DataFrame, i: int,
               apply_rr_filter: bool = False) -> dict | None:
    """Build a result dict for row i, or None if it fails a hard filter."""
    row = df.iloc[i]
    if not passes_universe(df, row):
        return None
    if not stage1_trend_ok(row):
        return None

    score, signals = score_row(df, i)
    if score == 0:
        return None

    entry = float(row["Close"])
    atr = float(row["atr"]) if not pd.isna(row["atr"]) else None
    if atr is None or atr <= 0:
        return None
    stop = entry - C.ATR_STOP_MULT * atr
    risk = entry - stop
    target = entry + C.BACKTEST_TARGET_R * risk  # target = entry + 2R
    reward = target - entry
    rr = reward / risk if risk > 0 else 0.0

    if apply_rr_filter and rr < C.MIN_REWARD_RISK:
        return None

    as_of = df.index[i]
    return {
        "symbol": symbol,
        "score": int(score),
        "entry_price": round(entry, 2),
        "stop_loss": round(stop, 2),
        "target": round(target, 2),
        "reward_risk_ratio": round(rr, 2),
        "pct_to_stop": round((stop - entry) / entry * 100, 2),
        "pct_to_target": round((target - entry) / entry * 100, 2),
        "signals_triggered": signals,
        "rsi": round(float(row["rsi"]), 1) if not pd.isna(row["rsi"]) else None,
        "as_of_date": str(as_of.date()) if hasattr(as_of, "date") else str(as_of),
        "based_on": f"Based on {as_of.date() if hasattr(as_of, 'date') else as_of} close",
        "disclaimer": DISCLAIMER,
    }


def scan_latest(data: dict[str, pd.DataFrame],
                apply_rr_filter: bool = False) -> list[dict]:
    """Compute picks for the most recent bar across the universe, ranked."""
    picks: list[dict] = []
    for sym, raw in data.items():
        if len(raw) < C.EMA_SLOW + 5:  # need enough history for EMA-200
            continue
        df = compute_indicators(raw)
        i = len(df) - 1
        pick = build_pick(sym, df, i, apply_rr_filter=apply_rr_filter)
        if pick:
            picks.append(pick)
    picks.sort(key=lambda p: p["score"], reverse=True)
    return picks
