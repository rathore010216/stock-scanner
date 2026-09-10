"""Central configuration for the NSE swing-trading scanner.

All tunable knobs live here so the scoring/backtest can be adjusted without
touching engine code.
"""

# ---- Universe filters (Section 2.3 of spec) ----
MIN_PRICE = 50.0            # exclude stocks priced below this (INR)
MIN_AVG_VOLUME_20 = 500_000  # exclude illiquid names (20-day avg shares)
# Market-cap filter is optional for MVP (needs extra data); off by default.
MIN_MARKET_CAP_CR = 0        # 0 = disabled; set to 500 to enable (INR crore)

# ---- Indicator parameters ----
EMA_FAST = 50
EMA_SLOW = 200
RSI_PERIOD = 14
MACD_FAST, MACD_SLOW, MACD_SIGNAL = 12, 26, 9
BB_PERIOD, BB_STD = 20, 2.0
ATR_PERIOD = 14
ADX_PERIOD = 14
ADX_STRONG = 25            # ADX above this = strong trend (momentum-friendly)
BREAKOUT_LOOKBACK = 20
VOL_AVG_PERIOD = 20

# ---- Scoring weights (Stage 2). Config-driven so we can tune via backtest. ----
SCORE = {
    "breakout_with_volume": 30,   # close > 20d high AND vol > 1.5x avg
    "breakout_only": 15,
    "bb_squeeze_release": 20,
    "rsi_sweet_spot": 20,         # 40..60
    "rsi_ok": 10,                 # 60..70
    "macd_cross_recent": 20,      # crossed up within last N days
    "volume_confirm": 10,         # vol > avg
}
MACD_CROSS_LOOKBACK = 3
VOLUME_SURGE_MULT = 1.5
BB_SQUEEZE_MONTHS = 6

# ---- Risk / reward (Stage 3) ----
ATR_STOP_MULT = 1.5
MIN_REWARD_RISK = 2.0

# ---- Backtest ----
BACKTEST_HOLD_DAYS = 15        # time-stop
BACKTEST_TARGET_R = 2.0        # target = entry + 2R (R = entry - stop)

# ---- Transaction costs (per round trip, % of turnover) ----
# Rough NSE delivery-equity estimates; tune to your broker.
COST_BROKERAGE_PCT = 0.0003    # ~0.03% (many discount brokers ~0 for delivery)
COST_STT_PCT = 0.001           # 0.1% STT on sell side (approx blended)
COST_SLIPPAGE_PCT = 0.0010     # 0.1% assumed slippage per side
# Total round-trip cost fraction applied to entry price in backtest.
ROUND_TRIP_COST_PCT = (COST_BROKERAGE_PCT * 2
                       + COST_STT_PCT
                       + COST_SLIPPAGE_PCT * 2)

# ---- Output ----
TOP_N = 10

# ---- Optional market regime filter ----
# If True, only suggest longs when the index is above its 200-EMA.
USE_REGIME_FILTER = False
REGIME_INDEX = "^CRSLDX"       # Nifty 500 index on Yahoo (fallback ^NSEI)

# ---- Toggleable screeners (manual scanning) ----
# Flip to True/False to choose which filters run in screen.py. Override at the
# command line with --only / --enable / --disable.
SCREENERS = {
    "trend": True,
    "breakout_52w": True,
    "rsi2": False,
    "volume_surge": True,
    "bollinger_squeeze": False,
    "macd_cross": False,
    "cup_handle": False,
    "momentum": True,   # cross-sectional 60-day top-decile
}

# When multiple screeners are on, require a stock to trigger AT LEAST this many
# to appear (1 = union / any; higher = intersection-style, more selective).
MIN_SCREENERS_TO_SHOW = 1
