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

/// Summary numbers computed by the backend from the full 2-year history.
class ChartStats {
  final Map<String, double> returns; // '1W','1M','3M','6M','1Y' -> %
  final double? high52, low52, pctFromHigh52, atrPct, volVsAvg, adx;
  final bool? aboveEma50, aboveEma200;

  const ChartStats({
    this.returns = const {},
    this.high52,
    this.low52,
    this.pctFromHigh52,
    this.atrPct,
    this.volVsAvg,
    this.adx,
    this.aboveEma50,
    this.aboveEma200,
  });

  static double? _n(dynamic v) => v is num ? v.toDouble() : null;

  factory ChartStats.fromMap(Map<dynamic, dynamic> m) {
    final r = <String, double>{};
    if (m['returns'] is Map) {
      (m['returns'] as Map).forEach((k, v) {
        if (v is num) r[k.toString()] = v.toDouble();
      });
    }
    return ChartStats(
      returns: r,
      high52: _n(m['high52']),
      low52: _n(m['low52']),
      pctFromHigh52: _n(m['pctFromHigh52']),
      atrPct: _n(m['atrPct']),
      volVsAvg: _n(m['volVsAvg']),
      adx: _n(m['adx']),
      aboveEma50: m['aboveEma50'] is bool ? m['aboveEma50'] as bool : null,
      aboveEma200: m['aboveEma200'] is bool ? m['aboveEma200'] as bool : null,
    );
  }
}

/// Per-symbol chart series from /stock/charts/{symbol}.
class ChartData {
  final List<String> dates;
  final List<double?> close, ema50, ema200, bbUpper, bbLower;
  final List<double?> macd, macdSignal, macdHist, rsi, volAvg20;
  final List<double?> volume;
  final ChartStats? stats; // null for charts published before stats existed

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
    this.stats,
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
      stats: m['stats'] is Map ? ChartStats.fromMap(m['stats'] as Map) : null,
    );
  }
}

/// One income-statement period (quarter or financial year). Values in ₹ crore.
class FinPeriod {
  final String period; // e.g. "Sep 26" or "FY26"
  final double? revenue, netProfit, opProfit;

  const FinPeriod(this.period, this.revenue, this.netProfit, this.opProfit);

  /// Net profit margin in %, or null.
  double? get netMargin => (revenue != null && revenue! != 0 && netProfit != null)
      ? netProfit! / revenue! * 100
      : null;

  factory FinPeriod.fromMap(Map<dynamic, dynamic> m) => FinPeriod(
        (m['period'] ?? '').toString(),
        _d(m['revenue']),
        _d(m['netProfit']),
        _d(m['opProfit']),
      );
}

double? _d(dynamic v) => v is num ? v.toDouble() : null;

/// Financials + key ratios from /stock/fundamentals/{symbol} (source: Yahoo).
/// Percent fields are already in % (e.g. roe 8.8 = 8.8%).
class Fundamentals {
  final String? name, sector, industry, ts;
  final double? marketCapCr, pe, pb, eps, bookValue, divYield, roe;
  final double? profitMargin, opMargin, debtToEquity;
  final double? revenueGrowth, earningsGrowth, high52, low52;
  final double? revenueTtmCr, netIncomeTtmCr;
  final List<FinPeriod> quarterly, annual; // oldest → newest

  const Fundamentals({
    this.name,
    this.sector,
    this.industry,
    this.ts,
    this.marketCapCr,
    this.pe,
    this.pb,
    this.eps,
    this.bookValue,
    this.divYield,
    this.roe,
    this.profitMargin,
    this.opMargin,
    this.debtToEquity,
    this.revenueGrowth,
    this.earningsGrowth,
    this.high52,
    this.low52,
    this.revenueTtmCr,
    this.netIncomeTtmCr,
    this.quarterly = const [],
    this.annual = const [],
  });

  static List<FinPeriod> _periods(dynamic v) => [
        if (v is List)
          for (final x in v)
            if (x is Map) FinPeriod.fromMap(x),
      ];

  factory Fundamentals.fromMap(Map<dynamic, dynamic> m) => Fundamentals(
        name: m['name']?.toString(),
        sector: m['sector']?.toString(),
        industry: m['industry']?.toString(),
        ts: m['ts']?.toString(),
        marketCapCr: _d(m['marketCapCr']),
        pe: _d(m['pe']),
        pb: _d(m['pb']),
        eps: _d(m['eps']),
        bookValue: _d(m['bookValue']),
        divYield: _d(m['divYield']),
        roe: _d(m['roe']),
        profitMargin: _d(m['profitMargin']),
        opMargin: _d(m['opMargin']),
        debtToEquity: _d(m['debtToEquity']),
        revenueGrowth: _d(m['revenueGrowth']),
        earningsGrowth: _d(m['earningsGrowth']),
        high52: _d(m['high52']),
        low52: _d(m['low52']),
        revenueTtmCr: _d(m['revenueTtmCr']),
        netIncomeTtmCr: _d(m['netIncomeTtmCr']),
        quarterly: _periods(m['quarterly']),
        annual: _periods(m['annual']),
      );
}
