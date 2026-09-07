import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

import '../models/stock_data.dart';

/// Reads the daily screener output from Firebase /stock/.
class StockService {
  final DatabaseReference _db = FirebaseDatabase.instance.ref();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Silent anonymous sign-in so ".read": "auth != null" is satisfied.
  Future<void> ensureSignedIn() async {
    if (_auth.currentUser == null) {
      await _auth.signInAnonymously();
    }
  }

  /// Fetch the latest scan: (asOf, disclaimer, allScreeners, matches).
  Future<
      ({
        String? asOf,
        String disclaimer,
        List<String> screeners,
        List<StockMatch> matches,
      })> fetchLatest() async {
    final snap = await _db.child('stock/latest').get();
    if (!snap.exists || snap.value == null) {
      return (
        asOf: null,
        disclaimer: '',
        screeners: <String>[],
        matches: <StockMatch>[]
      );
    }
    final m = snap.value as Map;
    final matches = <StockMatch>[];
    if (m['matches'] is List) {
      for (final item in (m['matches'] as List)) {
        if (item is Map) matches.add(StockMatch.fromMap(item));
      }
    }
    final screeners = <String>[];
    if (m['screeners'] is List) {
      for (final s in (m['screeners'] as List)) {
        screeners.add(s.toString());
      }
    }
    return (
      asOf: m['as_of']?.toString(),
      disclaimer: (m['disclaimer'] ?? '').toString(),
      screeners: screeners,
      matches: matches,
    );
  }

  /// Fetch one symbol's chart data on demand.
  Future<ChartData?> fetchChart(String symbol) async {
    final snap = await _db.child('stock/charts/$symbol').get();
    if (!snap.exists || snap.value == null) return null;
    return ChartData.fromMap(snap.value as Map);
  }

  /// Latest close + previous close for a symbol (for portfolio P/L + day P/L).
  /// Prefers the fresher intraday quote (/stock/quotes) if available, else
  /// falls back to the daily chart's last two closes.
  Future<({double last, double prev})?> lastTwoCloses(String symbol) async {
    // Try the intraday quote first.
    final qSnap = await _db.child('stock/quotes/$symbol').get();
    if (qSnap.exists && qSnap.value != null) {
      final q = qSnap.value as Map;
      final price = (q['price'] is num) ? (q['price'] as num).toDouble() : null;
      final prev =
          (q['prevClose'] is num) ? (q['prevClose'] as num).toDouble() : null;
      if (price != null) {
        return (last: price, prev: prev ?? price);
      }
    }
    // Fallback: daily chart closes.
    final chart = await fetchChart(symbol);
    if (chart == null) return null;
    final closes = chart.close.whereType<double>().toList();
    if (closes.isEmpty) return null;
    final last = closes.last;
    final prev = closes.length >= 2 ? closes[closes.length - 2] : last;
    return (last: last, prev: prev);
  }

  /// Map of symbol -> latest quote price (fresher than EOD). Empty if none.
  Future<Map<String, double>> fetchQuotes() async {
    final snap = await _db.child('stock/quotes').get();
    final out = <String, double>{};
    if (snap.exists && snap.value is Map) {
      (snap.value as Map).forEach((k, v) {
        if (v is Map && v['price'] is num) {
          out[k as String] = (v['price'] as num).toDouble();
        }
      });
    }
    return out;
  }

  /// When quotes were last refreshed (ISO string) or null.
  Future<String?> quotesAsOf() async {
    final snap = await _db.child('stock/quotesAsOf').get();
    return snap.value?.toString();
  }
}
