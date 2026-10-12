"""Shoonya (Finvasia) equity **delivery** charge model — Python port.

This MUST stay byte-for-byte equivalent to the Dart `Fees` class in
app/lib/services/portfolio_service.dart so that server-side auto-exits and
client-side manual sells compute identical fees and realized P/L.

All rates are on turnover (qty * price) unless noted. Delivery is the relevant
case for a swing/buy-and-hold paper tool.

Reference (shoonya.com/pricing, equity delivery):
 - Brokerage: Rs 0 (zero on delivery)
 - STT: 0.10% on BOTH buy and sell
 - Exchange transaction: 0.00297%
 - SEBI: Rs 10 per crore = 0.0001%
 - GST: 18% on (brokerage + txn + SEBI)
 - Stamp duty: 0.015% on BUY side only
 - DP charge: Rs 9 + GST per scrip on SELL (shares leaving demat)
"""
from __future__ import annotations

BROKERAGE = 0.0          # delivery
STT_PCT = 0.001          # 0.10% each side
TXN_PCT = 0.0000297      # 0.00297%
SEBI_PCT = 0.000001      # 0.0001% (Rs 10/cr)
GST_RATE = 0.18
STAMP_PCT = 0.00015      # 0.015% buy side only
DP_CHARGE = 9.0          # Rs 9 per scrip on sell


def fee_for_trade(is_buy: bool, turnover: float) -> float:
    """Total charges for one side of a delivery trade.

    Mirrors Dart `Fees.forTrade`:
      is_buy True  -> buy side (stamp applies)
      is_buy False -> sell side (STT both sides already + DP on sell)
    """
    stt = STT_PCT * turnover            # both sides
    txn = TXN_PCT * turnover
    sebi = SEBI_PCT * turnover
    gst = GST_RATE * (BROKERAGE + txn + sebi)
    total = BROKERAGE + stt + txn + sebi + gst
    if is_buy:
        total += STAMP_PCT * turnover   # stamp on buy only
    else:
        total += DP_CHARGE * (1 + GST_RATE)  # DP Rs 9 + GST on sell
    return total


if __name__ == "__main__":
    # Quick self-check against hand-computed values.
    # Sell 10 @ 100 => turnover 1000.
    #   stt  = 0.001    * 1000 = 1.0
    #   txn  = 0.0000297 * 1000 = 0.0297
    #   sebi = 0.000001 * 1000  = 0.001
    #   gst  = 0.18 * (0 + 0.0297 + 0.001) = 0.18 * 0.0307 = 0.005526
    #   dp   = 9 * 1.18 = 10.62
    #   total= 1.0 + 0.0297 + 0.001 + 0.005526 + 10.62 = 11.656226
    t = fee_for_trade(is_buy=False, turnover=1000.0)
    print(f"sell fee on 1000 turnover = {t:.6f}  (expect 11.656226)")
    b = fee_for_trade(is_buy=True, turnover=1000.0)
    #   buy: stamp = 0.00015*1000 = 0.15; no DP
    #   total = 1.0 + 0.0297 + 0.001 + 0.005526 + 0.15 = 1.186226
    print(f"buy  fee on 1000 turnover = {b:.6f}  (expect 1.186226)")
