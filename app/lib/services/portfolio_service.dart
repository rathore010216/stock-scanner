import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

/// A single holding.
class Holding {
  final String symbol;
  final int qty;
  final double avgPrice;
  final int firstBuyMs;

  /// Optional paper stop-loss / target price levels. Null = not set.
  final double? stopLoss;
  final double? target;

  /// Optional free-text note for research.
  final String? note;

  const Holding({
    required this.symbol,
    required this.qty,
    required this.avgPrice,
    required this.firstBuyMs,
    this.stopLoss,
    this.target,
    this.note,
  });

  double get invested => qty * avgPrice;

  factory Holding.fromMap(String symbol, Map m) => Holding(
        symbol: symbol,
        qty: (m['qty'] ?? 0) as int,
        avgPrice: (m['avgPrice'] is num) ? (m['avgPrice'] as num).toDouble() : 0,
        firstBuyMs: (m['firstBuyMs'] ?? 0) as int,
        stopLoss:
            (m['stopLoss'] is num) ? (m['stopLoss'] as num).toDouble() : null,
        target: (m['target'] is num) ? (m['target'] as num).toDouble() : null,
        note: (m['note'] is String && (m['note'] as String).trim().isNotEmpty)
            ? m['note'] as String
            : null,
      );

  /// True when a valid current price has crossed the stop-loss (<=).
  bool stopHit(double price) => stopLoss != null && price <= stopLoss!;

  /// True when a valid current price has reached the target (>=).
  bool targetHit(double price) => target != null && price >= target!;
}

/// One recorded buy or sell in the trade log.
class Trade {
  final String symbol;
  final bool isBuy;
  final int qty;
  final double price;
  final double? realizedPnl; // set on sells only
  final double fee; // charges paid on this trade
  final int ms;

  const Trade({
    required this.symbol,
    required this.isBuy,
    required this.qty,
    required this.price,
    required this.ms,
    this.realizedPnl,
    this.fee = 0,
  });

  factory Trade.fromMap(Map m) => Trade(
        symbol: (m['symbol'] ?? '').toString(),
        isBuy: (m['side'] ?? 'buy') == 'buy',
        qty: (m['qty'] ?? 0) as int,
        price: (m['price'] is num) ? (m['price'] as num).toDouble() : 0,
        realizedPnl: (m['realizedPnl'] is num)
            ? (m['realizedPnl'] as num).toDouble()
            : null,
        fee: (m['fee'] is num) ? (m['fee'] as num).toDouble() : 0,
        ms: (m['ms'] ?? 0) as int,
      );

  DateTime get time => DateTime.fromMillisecondsSinceEpoch(ms);
}

/// One point on the portfolio equity curve (daily total value snapshot).
class EquityPoint {
  final String date; // yyyy-MM-dd
  final double value;
  const EquityPoint(this.date, this.value);
}

/// One watchlist entry: a symbol with an optional research note.
class WatchItem {
  final String symbol;
  final String? note;
  const WatchItem(this.symbol, this.note);
}

/// Snapshot of the portfolio.
class Portfolio {
  final double cash;
  final double realizedPnl;
  final List<Holding> holdings;

  const Portfolio({
    required this.cash,
    required this.realizedPnl,
    required this.holdings,
  });
}

const double kStartingCapital = 100000.0;

/// Shoonya (Finvasia) equity **delivery** charge model. All rates are on
/// turnover (qty * price) unless noted. Delivery is the relevant case for a
/// swing/buy-and-hold paper tool.
///
/// Reference (shoonya.com/pricing, equity delivery):
///  - Brokerage: ₹0 (zero on delivery)
///  - STT: 0.10% on BOTH buy and sell
///  - Exchange transaction: 0.00297%
///  - SEBI: ₹10 per crore = 0.0001%
///  - GST: 18% on (brokerage + txn + SEBI)
///  - Stamp duty: 0.015% on BUY side only
///  - DP charge: ₹9 + GST per scrip on SELL (shares leaving demat)
class Fees {
  static const double brokerage = 0.0; // delivery
  static const double sttPct = 0.001; // 0.10% each side
  static const double txnPct = 0.0000297; // 0.00297%
  static const double sebiPct = 0.000001; // 0.0001% (₹10/cr)
  static const double gstRate = 0.18;
  static const double stampPct = 0.00015; // 0.015% buy side only
  static const double dpCharge = 9.0; // ₹9 per scrip on sell

  /// Total charges for one side of a delivery trade.
  /// [isBuy] true = buy side (stamp applies), false = sell (STT + DP apply too).
  static double forTrade({required bool isBuy, required double turnover}) {
    final stt = sttPct * turnover; // both sides
    final txn = txnPct * turnover;
    final sebi = sebiPct * turnover;
    final gst = gstRate * (brokerage + txn + sebi);
    double total = brokerage + stt + txn + sebi + gst;
    if (isBuy) {
      total += stampPct * turnover; // stamp on buy only
    } else {
      total += dpCharge * (1 + gstRate); // DP ₹9 + GST on sell
    }
    return total;
  }
}

/// Paper-trading portfolio stored at /portfolios/{uid}.
class PortfolioService {
  final DatabaseReference _db = FirebaseDatabase.instance.ref();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get _uid => _auth.currentUser!.uid;
  DatabaseReference get _ref => _db.child('portfolios/$_uid');

  /// Create the portfolio with starting capital if it doesn't exist yet.
  Future<void> ensureInit() async {
    final snap = await _ref.child('cash').get();
    if (!snap.exists) {
      await _ref.update({
        'cash': kStartingCapital,
        'realizedPnl': 0.0,
        'createdAt': ServerValue.timestamp,
      });
    }
  }

  Stream<Portfolio> stream() {
    return _ref.onValue.map((event) {
      final val = event.snapshot.value;
      if (val == null) {
        return const Portfolio(
            cash: kStartingCapital, realizedPnl: 0, holdings: []);
      }
      final m = val as Map;
      final holdings = <Holding>[];
      if (m['holdings'] is Map) {
        (m['holdings'] as Map).forEach((k, v) {
          if (v is Map && (v['qty'] ?? 0) > 0) {
            holdings.add(Holding.fromMap(k as String, v));
          }
        });
      }
      holdings.sort((a, b) => a.symbol.compareTo(b.symbol));
      return Portfolio(
        cash: (m['cash'] is num) ? (m['cash'] as num).toDouble()
            : kStartingCapital,
        realizedPnl:
            (m['realizedPnl'] is num) ? (m['realizedPnl'] as num).toDouble() : 0,
        holdings: holdings,
      );
    });
  }

  /// Buy [qty] shares of [symbol] at [price]. Throws StateError on bad input.
  Future<void> buy(String symbol, int qty, double price) async {
    if (qty <= 0) throw StateError('Quantity must be at least 1');
    final cost = qty * price;
    final fee = Fees.forTrade(isBuy: true, turnover: cost);
    final totalDebit = cost + fee;
    final snap = await _ref.get();
    final m = (snap.value as Map?) ?? {};
    final cash = (m['cash'] is num) ? (m['cash'] as num).toDouble()
        : kStartingCapital;
    if (totalDebit > cash) {
      throw StateError(
          'Not enough cash (need ₹${totalDebit.toStringAsFixed(0)} incl. '
          '₹${fee.toStringAsFixed(0)} fees, have ₹${cash.toStringAsFixed(0)})');
    }

    final holdings = (m['holdings'] as Map?) ?? {};
    final existing = holdings[symbol] as Map?;
    int newQty = qty;
    double newAvg = price;
    int firstBuy = DateTime.now().millisecondsSinceEpoch;
    // Preserve any previously set stop-loss / target when averaging up.
    Object? keepStop;
    Object? keepTarget;
    if (existing != null && (existing['qty'] ?? 0) > 0) {
      final eq = (existing['qty'] as num).toInt();
      final ep = (existing['avgPrice'] as num).toDouble();
      newQty = eq + qty;
      newAvg = (eq * ep + qty * price) / newQty;
      firstBuy = (existing['firstBuyMs'] ?? firstBuy) as int;
      keepStop = existing['stopLoss'];
      keepTarget = existing['target'];
    }

    await _ref.update({
      'cash': cash - totalDebit,
      'holdings/$symbol': {
        'qty': newQty,
        'avgPrice': newAvg,
        'firstBuyMs': firstBuy,
        if (keepStop != null) 'stopLoss': keepStop,
        if (keepTarget != null) 'target': keepTarget,
      },
    });

    // Log the trade (with the fee charged).
    await _ref.child('trades').push().set({
      'symbol': symbol,
      'side': 'buy',
      'qty': qty,
      'price': price,
      'fee': double.parse(fee.toStringAsFixed(2)),
      'ms': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Set or clear the paper stop-loss / target for a held [symbol].
  /// Pass null to clear a level. Throws if the symbol is not held.
  Future<void> setLevels(
      String symbol, double? stopLoss, double? target) async {
    final snap = await _ref.child('holdings/$symbol').get();
    if (!snap.exists || ((snap.value as Map)['qty'] ?? 0) <= 0) {
      throw StateError('You do not hold $symbol');
    }
    await _ref.update({
      'holdings/$symbol/stopLoss': stopLoss,
      'holdings/$symbol/target': target,
    });
  }

  /// Sell [qty] shares of [symbol] at [price]. Realizes P/L into cash.
  Future<void> sell(String symbol, int qty, double price) async {
    final snap = await _ref.get();
    final m = (snap.value as Map?) ?? {};
    final holdings = (m['holdings'] as Map?) ?? {};
    final existing = holdings[symbol] as Map?;
    if (existing == null || (existing['qty'] ?? 0) <= 0) {
      throw StateError('You do not hold $symbol');
    }
    final eq = (existing['qty'] as num).toInt();
    final ep = (existing['avgPrice'] as num).toDouble();
    if (qty <= 0 || qty > eq) {
      throw StateError('You hold $eq share(s)');
    }
    final proceeds = qty * price;
    final fee = Fees.forTrade(isBuy: false, turnover: proceeds);
    final netProceeds = proceeds - fee;
    // Realized P/L is net of the sell-side fee. (The buy-side fee was already
    // deducted from cash at purchase time.)
    final realized = (price - ep) * qty - fee;
    final cash = (m['cash'] is num) ? (m['cash'] as num).toDouble()
        : kStartingCapital;
    final prevRealized =
        (m['realizedPnl'] is num) ? (m['realizedPnl'] as num).toDouble() : 0;

    final updates = <String, Object?>{
      'cash': cash + netProceeds,
      'realizedPnl': prevRealized + realized,
    };
    if (qty == eq) {
      updates['holdings/$symbol'] = null; // fully closed
    } else {
      updates['holdings/$symbol/qty'] = eq - qty; // partial
    }
    await _ref.update(updates);

    // Log the trade with realized P/L (net of sell fee) and the fee charged.
    await _ref.child('trades').push().set({
      'symbol': symbol,
      'side': 'sell',
      'qty': qty,
      'price': price,
      'realizedPnl': double.parse(realized.toStringAsFixed(2)),
      'fee': double.parse(fee.toStringAsFixed(2)),
      'ms': DateTime.now().millisecondsSinceEpoch,
    });
  }

  // ---------------------------------------------------------------------------
  // Trade log
  // ---------------------------------------------------------------------------

  /// Stream of all trades, newest first.
  Stream<List<Trade>> tradesStream() {
    return _ref.child('trades').onValue.map((event) {
      final val = event.snapshot.value;
      final out = <Trade>[];
      if (val is Map) {
        val.forEach((_, v) {
          if (v is Map) out.add(Trade.fromMap(v));
        });
      }
      out.sort((a, b) => b.ms.compareTo(a.ms)); // newest first
      return out;
    });
  }

  // ---------------------------------------------------------------------------
  // Notes
  // ---------------------------------------------------------------------------

  /// Set or clear a free-text note on a held symbol. Empty string clears it.
  Future<void> setNote(String symbol, String note) async {
    final trimmed = note.trim();
    await _ref.child('holdings/$symbol/note').set(trimmed.isEmpty ? null : trimmed);
  }

  // ---------------------------------------------------------------------------
  // Watchlist  (/portfolios/{uid}/watchlist/{symbol} = {addedAt, note})
  // Legacy entries may be a plain number (addedMs); handled below.
  // ---------------------------------------------------------------------------

  Stream<List<WatchItem>> watchlistStream() {
    return _ref.child('watchlist').onValue.map((event) {
      final val = event.snapshot.value;
      final out = <WatchItem>[];
      if (val is Map) {
        val.forEach((k, v) {
          String? note;
          if (v is Map) {
            final n = v['note'];
            if (n is String && n.trim().isNotEmpty) note = n;
          }
          // Legacy value (plain number) → no note.
          out.add(WatchItem(k as String, note));
        });
      }
      out.sort((a, b) => a.symbol.compareTo(b.symbol));
      return out;
    });
  }

  Future<void> addToWatchlist(String symbol) async {
    final s = symbol.trim().toUpperCase();
    if (s.isEmpty) throw StateError('Enter a symbol');
    // Write only addedAt so an existing note (if any) is preserved.
    await _ref
        .child('watchlist/$s/addedAt')
        .set(DateTime.now().millisecondsSinceEpoch);
  }

  Future<void> removeFromWatchlist(String symbol) async {
    await _ref.child('watchlist/$symbol').remove();
  }

  /// Set or clear a note on a watchlist symbol. Empty string clears it.
  Future<void> setWatchlistNote(String symbol, String note) async {
    final trimmed = note.trim();
    await _ref
        .child('watchlist/$symbol/note')
        .set(trimmed.isEmpty ? null : trimmed);
  }

  // ---------------------------------------------------------------------------
  // Equity history  (/portfolios/{uid}/history/{yyyy-MM-dd} = totalValue)
  // ---------------------------------------------------------------------------

  /// Store today's total portfolio value (idempotent — overwrites today's key).
  Future<void> snapshotValue(double totalValue) async {
    final now = DateTime.now();
    final key = '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    await _ref.child('history/$key').set(totalValue);
  }

  Stream<List<EquityPoint>> historyStream() {
    return _ref.child('history').onValue.map((event) {
      final val = event.snapshot.value;
      final out = <EquityPoint>[];
      if (val is Map) {
        val.forEach((k, v) {
          if (v is num) out.add(EquityPoint(k as String, v.toDouble()));
        });
      }
      out.sort((a, b) => a.date.compareTo(b.date)); // oldest first
      return out;
    });
  }

  /// Reset the portfolio back to starting capital.
  Future<void> reset() async {
    await _ref.set({
      'cash': kStartingCapital,
      'realizedPnl': 0.0,
      'createdAt': ServerValue.timestamp,
    });
  }
}
