"""Transparent indicator implementations using pandas/numpy only.

No pandas-ta dependency (avoids version churn). Every indicator is computed
from OHLCV so the math is auditable. All functions return columns aligned to
the input index; the latest row is the most recent trading day.
"""
from __future__ import annotations

import numpy as np
import pandas as pd

import config as C


def ema(series: pd.Series, span: int) -> pd.Series:
    return series.ewm(span=span, adjust=False).mean()


def rsi_wilder(close: pd.Series, period: int = 14) -> pd.Series:
    """Wilder's RSI (uses Wilder smoothing = EMA with alpha=1/period)."""
    delta = close.diff()
    gain = delta.clip(lower=0.0)
    loss = -delta.clip(upper=0.0)
    avg_gain = gain.ewm(alpha=1 / period, adjust=False).mean()
    avg_loss = loss.ewm(alpha=1 / period, adjust=False).mean()
    rs = avg_gain / avg_loss.replace(0.0, np.nan)
    rsi = 100 - (100 / (1 + rs))
    # If avg_loss is 0 (all gains), RSI is 100.
    rsi = rsi.where(avg_loss != 0, 100.0)
    return rsi


def macd(close: pd.Series, fast=12, slow=26, signal=9):
    macd_line = ema(close, fast) - ema(close, slow)
    signal_line = macd_line.ewm(span=signal, adjust=False).mean()
    hist = macd_line - signal_line
    return macd_line, signal_line, hist


def bollinger(close: pd.Series, period=20, num_std=2.0):
    mid = close.rolling(period).mean()
    std = close.rolling(period).std(ddof=0)
    upper = mid + num_std * std
    lower = mid - num_std * std
    return upper, mid, lower


def atr(df: pd.DataFrame, period=14) -> pd.Series:
    """Average True Range (Wilder smoothing)."""
    high, low, close = df["High"], df["Low"], df["Close"]
    prev_close = close.shift(1)
    tr = pd.concat([
        (high - low),
        (high - prev_close).abs(),
        (low - prev_close).abs(),
    ], axis=1).max(axis=1)
    return tr.ewm(alpha=1 / period, adjust=False).mean()


def compute_indicators(df: pd.DataFrame) -> pd.DataFrame:
    """Add all indicator columns to a single stock's OHLCV DataFrame."""
    out = df.copy()
    close = out["Close"]

    out["ema_fast"] = ema(close, C.EMA_FAST)
    out["ema_slow"] = ema(close, C.EMA_SLOW)
    out["ema_short"] = ema(close, 20)  # short-term trend for pullback detection
    out["rsi"] = rsi_wilder(close, C.RSI_PERIOD)

    macd_line, signal_line, hist = macd(
        close, C.MACD_FAST, C.MACD_SLOW, C.MACD_SIGNAL)
    out["macd"] = macd_line
    out["macd_signal"] = signal_line
    out["macd_hist"] = hist

    upper, mid, lower = bollinger(close, C.BB_PERIOD, C.BB_STD)
    out["bb_upper"] = upper
    out["bb_mid"] = mid
    out["bb_lower"] = lower
    out["bb_bandwidth"] = (upper - lower) / mid.replace(0.0, np.nan)

    out["atr"] = atr(out, C.ATR_PERIOD)

    # Rolling 20-day high of High, EXCLUDING today (shift 1) for breakout ref.
    out["high_20_prev"] = out["High"].rolling(
        C.BREAKOUT_LOOKBACK).max().shift(1)
    out["vol_avg_20"] = out["Volume"].rolling(C.VOL_AVG_PERIOD).mean()

    # 6-month rolling low of bandwidth for squeeze detection (~126 trading days)
    lookback = C.BB_SQUEEZE_MONTHS * 21
    out["bb_bw_min_6mo"] = out["bb_bandwidth"].rolling(
        lookback, min_periods=20).min()

    return out
