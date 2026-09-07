"""Separate cup-and-handle pattern screener (its own view/mode).

This is a rules-based HEURISTIC detector, not ML. Cup-and-handle is inherently
fuzzy; parameters are tunable below. Like the score scanner, treat this as a
SCREENER that surfaces candidate shapes for human chart review -- not a
validated buy signal.

Definition used:
  CUP: over a window, a left rim high -> rounded decline to a bottom -> recovery
       to a right rim near the left rim (within RIM_TOLERANCE). Depth between
       MIN_DEPTH and MAX_DEPTH. Bottom should be roughly U-shaped (the min sits
       in the middle portion, not at an edge -> filters sharp V's).
  HANDLE: after the right rim, a shorter, shallow pullback (<= HANDLE_MAX_RETRACE
       of cup depth) over <= HANDLE_MAX_LEN bars, staying above the cup midpoint.
  TRIGGER (optional): latest close breaking above the handle high (breakout).

Usage:
    python cup_handle.py [--fresh] [--no-breakout]
"""
from __future__ import annotations

import argparse
import json
import os

import numpy as np
import pandas as pd

import config as C
from data_fetcher import fetch_all
from indicators import compute_indicators
from scoring import passes_universe, DISCLAIMER

OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "output")

# ---- Cup & handle heuristic parameters (tunable) ----
CUP_MIN_LEN = 20        # min bars for the cup
CUP_MAX_LEN = 130       # max bars for the cup
MIN_DEPTH = 0.12        # 12% min cup depth
MAX_DEPTH = 0.45        # 45% max cup depth
RIM_TOLERANCE = 0.06    # right rim within 6% of left rim
BOTTOM_MIDDLE_FRAC = 0.34  # cup low must sit within the middle ~1/3..2/3
HANDLE_MAX_LEN = 25
HANDLE_MAX_RETRACE = 0.5   # handle pullback <= 50% of cup depth
HANDLE_MIN_LEN = 3


def detect_cup_handle(df: pd.DataFrame,
                      require_breakout: bool = True) -> dict | None:
    """Detect the most recent cup-and-handle ending at/near the last bar."""
    close = df["Close"].values
    high = df["High"].values
    n = len(close)
    if n < CUP_MIN_LEN + HANDLE_MIN_LEN + 2:
        return None

    # The handle ends at the last bar. Search handle lengths, then a cup before.
    for handle_len in range(HANDLE_MIN_LEN, HANDLE_MAX_LEN + 1):
        handle_start = n - handle_len
        if handle_start <= CUP_MIN_LEN:
            break
        right_rim_idx = handle_start - 1
        right_rim = high[right_rim_idx]

        # Handle must be a shallow pullback below the right rim.
        handle_slice = close[handle_start:n]
        handle_low = handle_slice.min()
        handle_high = handle_slice.max()

        for cup_len in range(CUP_MIN_LEN, CUP_MAX_LEN + 1):
            cup_start = right_rim_idx - cup_len
            if cup_start < 0:
                break
            left_rim = high[cup_start]
            cup_region_low_idx = cup_start + int(
                np.argmin(close[cup_start:right_rim_idx + 1]))
            cup_low = close[cup_region_low_idx]

            # Rims roughly level.
            if abs(right_rim - left_rim) / left_rim > RIM_TOLERANCE:
                continue
            # Depth in range.
            depth = (max(left_rim, right_rim) - cup_low) / max(left_rim,
                                                               right_rim)
            if depth < MIN_DEPTH or depth > MAX_DEPTH:
                continue
            # Bottom roughly centered (U not V, not skewed).
            pos = (cup_region_low_idx - cup_start) / cup_len
            if pos < BOTTOM_MIDDLE_FRAC or pos > (1 - BOTTOM_MIDDLE_FRAC):
                continue
            # Handle shallow: retrace <= HANDLE_MAX_RETRACE of cup depth, and
            # handle stays in upper half of the cup.
            cup_mid = (max(left_rim, right_rim) + cup_low) / 2
            handle_retrace = (right_rim - handle_low) / (
                max(left_rim, right_rim) - cup_low)
            if handle_retrace > HANDLE_MAX_RETRACE:
                continue
            if handle_low < cup_mid:
                continue

            last_close = close[-1]
            breakout = last_close > handle_high and last_close > right_rim
            if require_breakout and not breakout:
                continue

            return {
                "cup_start_idx": cup_start,
                "cup_low_idx": cup_region_low_idx,
                "right_rim_idx": right_rim_idx,
                "cup_len": cup_len,
                "handle_len": handle_len,
                "left_rim": round(float(left_rim), 2),
                "right_rim": round(float(right_rim), 2),
                "cup_low": round(float(cup_low), 2),
                "depth_pct": round(depth * 100, 1),
                "handle_retrace_pct": round(handle_retrace * 100, 1),
                "handle_high": round(float(handle_high), 2),
                "breakout": bool(breakout),
                "last_close": round(float(last_close), 2),
            }
    return None


def scan_cup_handle(data: dict[str, pd.DataFrame],
                    require_breakout: bool = True) -> list[dict]:
    results = []
    for sym, raw in data.items():
        if len(raw) < CUP_MAX_LEN + HANDLE_MAX_LEN + 5:
            continue
        df = compute_indicators(raw)
        row = df.iloc[-1]
        if not passes_universe(df, row):
            continue
        det = detect_cup_handle(df, require_breakout=require_breakout)
        if not det:
            continue
        as_of = df.index[-1]
        # Suggested levels (screener-style): entry at breakout close, stop
        # below handle low / 1.5 ATR, target = cup depth projected from rim.
        entry = det["last_close"]
        atr = float(row["atr"]) if not pd.isna(row["atr"]) else None
        stop = round(entry - C.ATR_STOP_MULT * atr, 2) if atr else None
        # Classic C&H target: breakout point + cup depth.
        depth_abs = det["right_rim"] - det["cup_low"]
        target = round(det["right_rim"] + depth_abs, 2)
        results.append({
            "symbol": sym,
            "pattern": "cup_and_handle",
            "breakout": det["breakout"],
            "entry_price": entry,
            "stop_loss": stop,
            "target": target,
            "cup_depth_pct": det["depth_pct"],
            "handle_retrace_pct": det["handle_retrace_pct"],
            "cup_len_bars": det["cup_len"],
            "handle_len_bars": det["handle_len"],
            "rsi": round(float(row["rsi"]), 1) if not pd.isna(row["rsi"]) else None,
            "as_of_date": str(as_of.date()),
            "disclaimer": DISCLAIMER,
        })
    # Breakouts first, then deeper/cleaner cups.
    results.sort(key=lambda r: (r["breakout"], -r["handle_retrace_pct"]),
                 reverse=True)
    return results


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fresh", action="store_true")
    ap.add_argument("--no-breakout", action="store_true",
                    help="include forming patterns that haven't broken out yet")
    args = ap.parse_args()

    data = fetch_all(period="2y", use_cache=not args.fresh)
    require_breakout = not args.no_breakout
    print(f"Scanning {len(data)} symbols for cup-and-handle "
          f"(breakout required: {require_breakout}) ...")
    res = scan_cup_handle(data, require_breakout=require_breakout)

    if not res:
        print("No cup-and-handle patterns found today.")
    else:
        print(f"\n=== Cup & Handle screener ({res[0]['as_of_date']}) ===")
        hdr = (f"{'SYMBOL':<12} {'BRK':>4} {'ENTRY':>9} {'STOP':>9} "
               f"{'TARGET':>9} {'DEPTH':>6} {'HANDLE':>7} {'RSI':>5}")
        print(hdr)
        print("-" * len(hdr))
        for r in res:
            print(f"{r['symbol']:<12} {'Y' if r['breakout'] else 'n':>4} "
                  f"{r['entry_price']:>9} {str(r['stop_loss']):>9} "
                  f"{r['target']:>9} {r['cup_depth_pct']:>5}% "
                  f"{r['handle_retrace_pct']:>6}% {str(r['rsi']):>5}")

    os.makedirs(OUTPUT_DIR, exist_ok=True)
    as_of = res[0]["as_of_date"] if res else "none"
    out = os.path.join(OUTPUT_DIR, f"cup_handle_{as_of}.json")
    with open(out, "w") as f:
        json.dump({"as_of_date": as_of, "patterns": res,
                   "disclaimer": DISCLAIMER}, f, indent=2)
    print(f"\n{DISCLAIMER}")
    print(f"Saved {len(res)} pattern(s) to {out}")


if __name__ == "__main__":
    main()
