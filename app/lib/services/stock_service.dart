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
  /// Returns (last, prev) or null if unavailable.
  Future<({double last, double prev})?> lastTwoCloses(String symbol) async {
    final chart = await fetchChart(symbol);
    if (chart == null) return null;
    final closes = chart.close.whereType<double>().toList();
    if (closes.isEmpty) return null;
    final last = closes.last;
    final prev = closes.length >= 2 ? closes[closes.length - 2] : last;
    return (last: last, prev: prev);
  }
}
