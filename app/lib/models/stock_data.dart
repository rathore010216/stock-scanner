/// A screener match from /stock/latest.
class StockMatch {
  final String symbol;
  final double price;
  final double? rsi;
  final List<String> triggered;

  const StockMatch({
    required this.symbol,
    required this.price,
    required this.rsi,
    required this.triggered,
  });

  int get numTriggered => triggered.length;

  factory StockMatch.fromMap(Map<dynamic, dynamic> m) {
    final trig = <String>[];
    if (m['triggered'] is List) {
      for (final t in (m['triggered'] as List)) {
        if (t != null) trig.add(t.toString());
      }
    }
    return StockMatch(
      symbol: (m['symbol'] ?? '').toString(),
      price: (m['price'] is num) ? (m['price'] as num).toDouble() : 0.0,
      rsi: (m['rsi'] is num) ? (m['rsi'] as num).toDouble() : null,
      triggered: trig,
    );
  }
}

/// Per-symbol chart series from /stock/charts/{symbol}.
class ChartData {
  final List<String> dates;
  final List<double?> close, ema50, ema200, bbUpper, bbLower;
  final List<double?> macd, macdSignal, macdHist, rsi, volAvg20;
  final List<double?> volume;

  const ChartData({
    required this.dates,
    required this.close,
    required this.ema50,
    required this.ema200,
    required this.bbUpper,
    required this.bbLower,
    required this.macd,
    required this.macdSignal,
    required this.macdHist,
    required this.rsi,
    required this.volAvg20,
    required this.volume,
  });

  static List<double?> _nums(dynamic v) {
    final out = <double?>[];
    if (v is List) {
      for (final x in v) {
        out.add((x is num) ? x.toDouble() : null);
      }
    }
    return out;
  }

  static List<String> _strs(dynamic v) {
    final out = <String>[];
    if (v is List) {
      for (final x in v) {
        out.add(x?.toString() ?? '');
      }
    }
    return out;
  }

  factory ChartData.fromMap(Map<dynamic, dynamic> m) {
    return ChartData(
      dates: _strs(m['dates']),
      close: _nums(m['close']),
      ema50: _nums(m['ema50']),
      ema200: _nums(m['ema200']),
      bbUpper: _nums(m['bb_upper']),
      bbLower: _nums(m['bb_lower']),
      macd: _nums(m['macd']),
      macdSignal: _nums(m['macd_signal']),
      macdHist: _nums(m['macd_hist']),
      rsi: _nums(m['rsi']),
      volAvg20: _nums(m['vol_avg20']),
      volume: _nums(m['volume']),
    );
  }
}
