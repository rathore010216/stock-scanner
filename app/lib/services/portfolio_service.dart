import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

/// A single holding.
class Holding {
  final String symbol;
  final int qty;
  final double avgPrice;
  final int firstBuyMs;

  const Holding({
    required this.symbol,
    required this.qty,
    required this.avgPrice,
    required this.firstBuyMs,
  });

  double get invested => qty * avgPrice;

  factory Holding.fromMap(String symbol, Map m) => Holding(
        symbol: symbol,
        qty: (m['qty'] ?? 0) as int,
        avgPrice: (m['avgPrice'] is num) ? (m['avgPrice'] as num).toDouble() : 0,
        firstBuyMs: (m['firstBuyMs'] ?? 0) as int,
      );
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
    final snap = await _ref.get();
    final m = (snap.value as Map?) ?? {};
    final cash = (m['cash'] is num) ? (m['cash'] as num).toDouble()
        : kStartingCapital;
    if (cost > cash) {
      throw StateError('Not enough cash (need ₹${cost.toStringAsFixed(0)}, '
          'have ₹${cash.toStringAsFixed(0)})');
    }

    final holdings = (m['holdings'] as Map?) ?? {};
    final existing = holdings[symbol] as Map?;
    int newQty = qty;
    double newAvg = price;
    int firstBuy = DateTime.now().millisecondsSinceEpoch;
    if (existing != null && (existing['qty'] ?? 0) > 0) {
      final eq = (existing['qty'] as num).toInt();
      final ep = (existing['avgPrice'] as num).toDouble();
      newQty = eq + qty;
      newAvg = (eq * ep + qty * price) / newQty;
      firstBuy = (existing['firstBuyMs'] ?? firstBuy) as int;
    }

    await _ref.update({
      'cash': cash - cost,
      'holdings/$symbol': {
        'qty': newQty,
        'avgPrice': newAvg,
        'firstBuyMs': firstBuy,
      },
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
    final realized = (price - ep) * qty;
    final cash = (m['cash'] is num) ? (m['cash'] as num).toDouble()
        : kStartingCapital;
    final prevRealized =
        (m['realizedPnl'] is num) ? (m['realizedPnl'] as num).toDouble() : 0;

    final updates = <String, Object?>{
      'cash': cash + proceeds,
      'realizedPnl': prevRealized + realized,
    };
    if (qty == eq) {
      updates['holdings/$symbol'] = null; // fully closed
    } else {
      updates['holdings/$symbol/qty'] = eq - qty; // partial
    }
    await _ref.update(updates);
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
