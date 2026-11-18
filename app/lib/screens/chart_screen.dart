import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/stock_data.dart';
import '../services/portfolio_service.dart';
import '../services/stock_service.dart';
import '../widgets/responsive.dart';
import '../widgets/updated_at.dart';
import 'matches_screen.dart' show screenerLabels;

class ChartScreen extends StatefulWidget {
  final String symbol;
  /// Screener keys that flagged this stock, when the caller already knows
  /// them (Screener tab). Otherwise they're looked up from the latest scan.
  final List<String>? triggered;
  /// Set when shown in the desktop web side pane: adds a close (X) button.
  final VoidCallback? onClose;
  const ChartScreen(
      {super.key, required this.symbol, this.triggered, this.onClose});

  @override
  State<ChartScreen> createState() => _ChartScreenState();
}

class _ChartScreenState extends State<ChartScreen> {
  final _service = StockService();
  ChartData? _data;
  bool _loading = true;
  String? _error;
  int _rangeDays = 63; // default ~3 months

  // Financials tab (loaded independently so a slow/missing record never
  // blocks the chart).
  Fundamentals? _fin;
  bool _finLoading = true;
  String? _finError;

  // Live price (from /stock/quotes), your holding of this stock (if any), and
  // which screeners flagged it.
  final _portfolio = PortfolioService();
  StreamSubscription? _quoteSub, _portfolioSub;
  ({double price, double prevClose})? _quote;
  Holding? _holding;
  double _cash = 0;
  List<String> _triggered = const [];

  @override
  void initState() {
    super.initState();
    _load();
    _loadFinancials();
    _quoteSub = _service.quotesStream().listen((q) {
      final v = q[widget.symbol];
      if (mounted && v != null) setState(() => _quote = v);
    }, onError: (_) {});
    _portfolioSub = _portfolio.stream().listen((p) {
      if (!mounted) return;
      Holding? held;
      for (final h in p.holdings) {
        if (h.symbol == widget.symbol && h.qty > 0) held = h;
      }
      setState(() {
        _cash = p.cash;
        _holding = held;
      });
    }, onError: (_) {});
    if (widget.triggered != null) {
      _triggered = widget.triggered!;
    } else {
      _service.triggeredFor(widget.symbol).then((t) {
        if (mounted) setState(() => _triggered = t);
      }).catchError((_) {});
    }
  }

  @override
  void dispose() {
    _quoteSub?.cancel();
    _portfolioSub?.cancel();
    super.dispose();
  }

  Future<void> _loadFinancials() async {
    try {
      final f = await _service
          .fetchFundamentals(widget.symbol)
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      setState(() {
        _fin = f;
        _finLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _finLoading = false;
        _finError = 'Could not load financials.\n$e';
      });
    }
  }

  Future<void> _load() async {
    try {
      final c = await _service.fetchChart(widget.symbol);
      if (!mounted) return;
      setState(() {
        _data = c;
        _loading = false;
        if (c == null) _error = 'No chart data for ${widget.symbol}.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load chart.\n$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.symbol),
          automaticallyImplyLeading: widget.onClose == null,
          actions: [
            if (widget.onClose != null)
              IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close),
                onPressed: widget.onClose,
              ),
          ],
          bottom: const TabBar(tabs: [
            Tab(text: 'Chart'),
            Tab(text: 'Financials'),
          ]),
        ),
        body: TabBarView(
            // Tap tabs to switch; swiping would fight the chart crosshair drag.
            physics: const NeverScrollableScrollPhysics(),
            children: [
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text(_error!, textAlign: TextAlign.center))
                  : _buildChart(),
          _buildFinancials(),
        ]),
      ),
    );
  }

  // Build spots from a series, skipping nulls (x = index).
  List<FlSpot> _spots(List<double?> series) {
    final spots = <FlSpot>[];
    for (var i = 0; i < series.length; i++) {
      final v = series[i];
      if (v != null) spots.add(FlSpot(i.toDouble(), v));
    }
    return spots;
  }

  double _min(List<List<double?>> series) {
    double m = double.infinity;
    for (final s in series) {
      for (final v in s) {
        if (v != null && v < m) m = v;
      }
    }
    return m == double.infinity ? 0 : m;
  }

  double _max(List<List<double?>> series) {
    double m = -double.infinity;
    for (final s in series) {
      for (final v in s) {
        if (v != null && v > m) m = v;
      }
    }
    return m == -double.infinity ? 1 : m;
  }

  // Slice the last N bars from a series.
  List<double?> _tail(List<double?> s, int n) =>
      s.length <= n ? s : s.sublist(s.length - n);

  Widget _rangeSelector() {
    final options = <String, int>{
      '1M': 21,
      '3M': 63,
      '6M': 126,
      'Max': 100000,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 8,
        children: [
          for (final e in options.entries)
            ChoiceChip(
              label: Text(e.key),
              selected: _rangeDays == e.value,
              onSelected: (_) => setState(() => _rangeDays = e.value),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }

  Widget _buildChart() {
    final full = _data!;
    final r = _rangeDays;
    // Sliced view for the selected range.
    final d = ChartData(
      dates: full.dates.length <= r
          ? full.dates
          : full.dates.sublist(full.dates.length - r),
      close: _tail(full.close, r),
      ema50: _tail(full.ema50, r),
      ema200: _tail(full.ema200, r),
      bbUpper: _tail(full.bbUpper, r),
      bbLower: _tail(full.bbLower, r),
      macd: _tail(full.macd, r),
      macdSignal: _tail(full.macdSignal, r),
      macdHist: _tail(full.macdHist, r),
      rsi: _tail(full.rsi, r),
      volAvg20: _tail(full.volAvg20, r),
      volume: _tail(full.volume, r),
    );
    final n = d.close.length;

    // Price-panel range, widened to include your avg buy price so its line is
    // always visible. SL/target lines are drawn only if they fall in range.
    var minY = _min([d.bbLower, d.close, d.ema200]) * 0.99;
    var maxY = _max([d.bbUpper, d.close]) * 1.01;
    final h = _holding;
    if (h != null) {
      if (h.avgPrice * 0.99 < minY) minY = h.avgPrice * 0.99;
      if (h.avgPrice * 1.01 > maxY) maxY = h.avgPrice * 1.01;
    }
    final levels = <(double, Color)>[
      if (h != null) (h.avgPrice, Colors.orange.shade700),
      if (h?.stopLoss != null) (h!.stopLoss!, Colors.red.shade400),
      if (h?.target != null) (h!.target!, Colors.green.shade600),
    ].where((l) => l.$1 >= minY && l.$1 <= maxY).toList();

    final topSection = <Widget>[
      const UpdatedAtLabel(),
      if (full.dates.isNotEmpty)
        Text('Chart data to ${full.dates.last} close',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.grey.shade700)),
      const SizedBox(height: 8),
      _summaryHeader(full),
      if (_triggered.isNotEmpty) ...[
        const SizedBox(height: 8),
        _tagsRow(),
      ],
      if (full.stats != null && full.stats!.returns.isNotEmpty) ...[
        const SizedBox(height: 12),
        _panelTitle('Returns'),
        _returnsRow(full.stats!.returns),
      ],
      const SizedBox(height: 12),
      _positionCard(full),
      const SizedBox(height: 12),
    ];

    final chartSection = <Widget>[
        _rangeSelector(),
        _panelTitle('Price · EMA50 · EMA200 · Bollinger'),
        _lineChart(
          height: isWideWeb(context) ? 420 : 260,
          lines: [
            _line(_spots(d.bbUpper), Colors.grey.shade400, width: 1),
            _line(_spots(d.bbLower), Colors.grey.shade400, width: 1),
            _line(_spots(d.close), Colors.black, width: 1.6),
            _line(_spots(d.ema50), Colors.blue, width: 1.2),
            _line(_spots(d.ema200), Colors.red, width: 1.2),
          ],
          minY: minY,
          maxY: maxY,
          n: n,
          dates: d.dates,
          valuePrefix: '₹',
          primaryBarIndex: 2, // the Close line
          levels: levels,
        ),
        _legend({
          'Close': Colors.black,
          'EMA50': Colors.blue,
          'EMA200': Colors.red,
          'Bollinger': Colors.grey,
          if (h != null) 'Your avg buy': Colors.orange.shade700,
          if (h?.stopLoss != null) 'Stop-loss': Colors.red.shade400,
          if (h?.target != null) 'Target': Colors.green.shade600,
        }),
        const SizedBox(height: 16),
        _panelTitle('Volume · blue = up day, red = down day'),
        _volumeChart(d, n),
        _legend({
          'Up day': Colors.blue.shade400,
          'Down day': Colors.red.shade400,
        }),
        const SizedBox(height: 16),
        _panelTitle('MACD (12,26,9)'),
        _lineChart(
          height: 160,
          lines: [
            _line(_spots(d.macd), Colors.blue, width: 1.2),
            _line(_spots(d.macdSignal), Colors.red, width: 1.2),
          ],
          minY: _min([d.macd, d.macdSignal, d.macdHist]) * 1.1,
          maxY: _max([d.macd, d.macdSignal, d.macdHist]) * 1.1,
          n: n,
          zeroLine: true,
          dates: d.dates,
        ),
        _legend(const {'MACD': Colors.blue, 'Signal': Colors.red}),
        const SizedBox(height: 16),
        _panelTitle('RSI (14)'),
        _lineChart(
          height: 140,
          lines: [_line(_spots(d.rsi), Colors.purple, width: 1.2)],
          minY: 0,
          maxY: 100,
          n: n,
          extraLines: [30, 50, 70],
          dates: d.dates,
        ),
        const SizedBox(height: 24),
    ];

    // Desktop web with a wide pane: summary/position on the left, charts on
    // the right, each scrolling on its own. Phone: one column, as before.
    return LayoutBuilder(builder: (context, box) {
      if (isWideWeb(context) && box.maxWidth >= 900) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 360,
              child: ListView(
                  padding: const EdgeInsets.all(12), children: topSection),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: ListView(
                  padding: const EdgeInsets.all(12), children: chartSection),
            ),
          ],
        );
      }
      return ListView(
        padding: const EdgeInsets.all(12),
        children: [...topSection, ...chartSection],
      );
    });
  }

  Widget _panelTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.bold)),
      );

  LineChartBarData _line(List<FlSpot> spots, Color color,
          {double width = 1}) =>
      LineChartBarData(
        spots: spots,
        isCurved: false,
        color: color,
        barWidth: width,
        dotData: const FlDotData(show: false),
      );

  Widget _lineChart({
    required double height,
    required List<LineChartBarData> lines,
    required double minY,
    required double maxY,
    required int n,
    bool zeroLine = false,
    List<double> extraLines = const [],
    List<String>? dates, // when provided, tap shows date + value
    String valuePrefix = '',
    int primaryBarIndex = 0, // which line's value to show in the tooltip
    List<(double, Color)> levels = const [], // dashed price levels (avg/SL/TGT)
  }) {
    final hLines = <HorizontalLine>[];
    for (final (y, color) in levels) {
      hLines.add(HorizontalLine(
          y: y, color: color, strokeWidth: 1.2, dashArray: [6, 4]));
    }
    if (zeroLine) {
      hLines.add(HorizontalLine(y: 0, color: Colors.black26, strokeWidth: 0.8));
    }
    for (final y in extraLines) {
      hLines.add(HorizontalLine(
          y: y,
          color: y == 50 ? Colors.grey.shade300 : Colors.redAccent.shade100,
          strokeWidth: 0.6,
          dashArray: [4, 4]));
    }
    // Which bar index carries the "main" value we want in the tooltip — the
    // last line added is the primary series for MACD/RSI; for the price panel
    // we mark the Close line explicitly via [primaryBarIndex].
    return SizedBox(
      height: height,
      child: LineChart(LineChartData(
        minX: 0,
        maxX: (n - 1).toDouble(),
        minY: minY,
        maxY: maxY,
        lineBarsData: lines,
        extraLinesData: ExtraLinesData(horizontalLines: hLines),
        titlesData: const FlTitlesData(
          leftTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 44)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(
            show: true, border: Border.all(color: Colors.grey.shade300)),
        // Google-Finance-style crosshair + tooltip: tap/drag shows the date
        // and value at that point. A vertical indicator line is drawn.
        lineTouchData: LineTouchData(
          enabled: true,
          getTouchedSpotIndicator: (barData, indexes) {
            return indexes.map((i) {
              return TouchedSpotIndicatorData(
                const FlLine(color: Colors.black38, strokeWidth: 1),
                FlDotData(
                  // Only draw the dot on the primary series for a clean look.
                  show: true,
                  getDotPainter: (spot, percent, bar, index) {
                    final isPrimary = lines.isNotEmpty &&
                        bar == lines[primaryBarIndex.clamp(0, lines.length - 1)];
                    return FlDotCirclePainter(
                      radius: isPrimary ? 4 : 0,
                      color: bar.color ?? Colors.black,
                      strokeWidth: 0,
                    );
                  },
                ),
              );
            }).toList();
          },
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => Colors.black87,
            maxContentWidth: 160,
            getTooltipItems: (spots) {
              // Show the date + the primary series' value once; suppress the
              // other overlapping lines so the tooltip stays clean.
              return spots.map((s) {
                if (s.barIndex != primaryBarIndex) return null;
                final xi = s.x.round();
                final dateStr = (dates != null && xi >= 0 && xi < dates.length)
                    ? dates[xi]
                    : '';
                final valStr = '$valuePrefix${s.y.toStringAsFixed(2)}';
                return LineTooltipItem(
                  dateStr.isEmpty ? valStr : '$dateStr\n$valStr',
                  const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600),
                );
              }).toList();
            },
          ),
          handleBuiltInTouches: true,
        ),
      )),
    );
  }

  Widget _volumeChart(ChartData d, int n) {
    final bars = <BarChartGroupData>[];
    double maxV = 1;
    for (var i = 0; i < d.volume.length; i++) {
      final v = d.volume[i] ?? 0;
      if (v > maxV) maxV = v;
      // Color by up/down day: close vs previous close. Blue = up day (buying
      // pressure), red = down day (selling pressure). This is the standard
      // OHLCV proxy — real buy/sell split needs tick data we don't have.
      final close = d.close[i];
      final prevClose = i > 0 ? d.close[i - 1] : null;
      final Color barColor;
      if (close == null || prevClose == null) {
        barColor = Colors.blueGrey.shade300; // unknown direction
      } else if (close >= prevClose) {
        barColor = Colors.blue.shade400; // up day → "bought"
      } else {
        barColor = Colors.red.shade400; // down day → "sold"
      }
      bars.add(BarChartGroupData(x: i, barRods: [
        BarChartRodData(toY: v, color: barColor, width: 2),
      ]));
    }
    return SizedBox(
      height: 130,
      child: BarChart(BarChartData(
        maxY: maxV * 1.1,
        barGroups: bars,
        titlesData: const FlTitlesData(
          leftTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 44)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(
            show: true, border: Border.all(color: Colors.grey.shade300)),
      )),
    );
  }

  Widget _legend(Map<String, Color> items) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Wrap(
          spacing: 12,
          children: [
            for (final e in items.entries)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 12, height: 3, color: e.value),
                const SizedBox(width: 4),
                Text(e.key, style: const TextStyle(fontSize: 11)),
              ]),
          ],
        ),
      );

  // ---------------------------------------------------------------------------
  // Chart tab: summary header, tags, returns, your position, buy/sell
  // ---------------------------------------------------------------------------

  static double? _lastNum(List<double?> s, {int back = 0}) {
    var seen = 0;
    for (var i = s.length - 1; i >= 0; i--) {
      if (s[i] != null) {
        if (seen == back) return s[i];
        seen++;
      }
    }
    return null;
  }

  /// Live price if we have a quote, else the chart's last close.
  ({double price, double prev})? _priceNow(ChartData full) {
    final q = _quote;
    if (q != null) return (price: q.price, prev: q.prevClose);
    final last = _lastNum(full.close);
    if (last == null) return null;
    return (price: last, prev: _lastNum(full.close, back: 1) ?? last);
  }

  Widget _summaryHeader(ChartData full) {
    final px = _priceNow(full);
    final st = full.stats;
    final rsi = _lastNum(full.rsi);
    final chg = px == null ? null : px.price - px.prev;
    final chgPct = (px == null || px.prev == 0) ? null : chg! / px.prev * 100;
    final c = _signColor(chg) ?? Colors.black87;

    Widget chip(String text, Color color) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Text(text,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: color)),
        );

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(px == null ? '—' : '₹${px.price.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontSize: 26, fontWeight: FontWeight.bold)),
                const SizedBox(width: 10),
                if (chg != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '${chg >= 0 ? '+' : ''}${chg.toStringAsFixed(2)} '
                      '(${_pct(chgPct, signed: true)}) today',
                      style: TextStyle(
                          color: c, fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            _statsGrid([
              ('RSI (14)', rsi == null ? '—' : rsi.toStringAsFixed(1),
                  rsi == null
                      ? null
                      : rsi >= 70
                          ? Colors.red.shade700
                          : rsi <= 30
                              ? Colors.green.shade700
                              : null),
              ('From 52w high', _pct(st?.pctFromHigh52, signed: true),
                  _signColor(st?.pctFromHigh52)),
              ('52-week high', _x(st?.high52, prefix: '₹'), null),
              ('52-week low', _x(st?.low52, prefix: '₹'), null),
              ('Volume vs 20d avg', _x(st?.volVsAvg, suffix: '×'), null),
              ('Daily range (ATR)', _pct(st?.atrPct), null),
            ]),
            if (st?.aboveEma50 != null ||
                st?.aboveEma200 != null ||
                st?.adx != null) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: [
                if (st?.aboveEma50 != null)
                  chip(st!.aboveEma50! ? 'Above EMA50' : 'Below EMA50',
                      st.aboveEma50! ? Colors.green.shade700 : Colors.red.shade700),
                if (st?.aboveEma200 != null)
                  chip(st!.aboveEma200! ? 'Above EMA200' : 'Below EMA200',
                      st.aboveEma200! ? Colors.green.shade700 : Colors.red.shade700),
                if (st?.adx != null)
                  chip(
                      'ADX ${st!.adx!.toStringAsFixed(0)} · '
                      '${st.adx! >= 25 ? 'strong trend' : st.adx! < 20 ? 'weak / choppy' : 'moderate'}',
                      st.adx! >= 25 ? Colors.blue.shade700 : Colors.grey.shade700),
              ]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tagsRow() => Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('Flagged by:',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
          for (final t in _triggered)
            Chip(
              label: Text(screenerLabels[t] ?? t,
                  style: const TextStyle(fontSize: 11)),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: EdgeInsets.zero,
            ),
        ],
      );

  Widget _returnsRow(Map<String, double> returns) {
    const order = ['1W', '1M', '3M', '6M', '1Y'];
    return Row(
      children: [
        for (final k in order)
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: (_signColor(returns[k]) ?? Colors.grey)
                    .withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                children: [
                  Text(k,
                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  const SizedBox(height: 2),
                  Text(_pct(returns[k], signed: true),
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _signColor(returns[k]))),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _positionCard(ChartData full) {
    final px = _priceNow(full);
    final h = _holding;
    final buyBtn = FilledButton.icon(
      onPressed: px == null ? null : () => _showBuy(px.price),
      icon: const Icon(Icons.add_shopping_cart, size: 18),
      label: const Text('Buy'),
    );
    if (h == null) {
      return Row(children: [
        const Expanded(
          child: Text("You don't hold this stock.",
              style: TextStyle(color: Colors.grey)),
        ),
        buyBtn,
      ]);
    }
    final price = px?.price ?? h.avgPrice;
    final prev = px?.prev ?? price;
    final value = h.qty * price;
    final pnl = (price - h.avgPrice) * h.qty;
    final pnlPct = h.avgPrice > 0 ? (price - h.avgPrice) / h.avgPrice * 100 : 0.0;
    final dayPnl = (price - prev) * h.qty;
    String money(double v) => '${v >= 0 ? '+' : '-'}₹${_inr(v.abs(), decimals: 2)}';
    return Card(
      margin: EdgeInsets.zero,
      color: Colors.orange.withValues(alpha: 0.05),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('YOUR POSITION',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey)),
            const SizedBox(height: 6),
            Text('${h.qty} shares @ avg ₹${h.avgPrice.toStringAsFixed(2)}  ·  '
                'value ₹${_inr(value, decimals: 2)}'),
            const SizedBox(height: 4),
            Text('P/L ${money(pnl)} (${_pct(pnlPct, signed: true)})',
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: _signColor(pnl))),
            Text("Today ${money(dayPnl)}",
                style: TextStyle(fontSize: 12, color: _signColor(dayPnl))),
            if (h.stopLoss != null || h.target != null)
              Text(
                [
                  if (h.stopLoss != null) 'SL ₹${h.stopLoss!.toStringAsFixed(2)}',
                  if (h.target != null) 'Target ₹${h.target!.toStringAsFixed(2)}',
                ].join('  ·  '),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            const SizedBox(height: 8),
            Row(children: [
              buyBtn,
              const SizedBox(width: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                onPressed: () => _showSell(h, price),
                icon: const Icon(Icons.sell_outlined, size: 18),
                label: const Text('Sell'),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  void _snack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _showBuy(double lastPrice) async {
    final priceCtl = TextEditingController(text: lastPrice.toStringAsFixed(2));
    final qtyCtl = TextEditingController(text: '1');
    final result = await showDialog<({int qty, double price})>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        final qty = int.tryParse(qtyCtl.text) ?? 0;
        final price = double.tryParse(priceCtl.text) ?? 0;
        final cost = qty * price;
        final fee = Fees.forTrade(isBuy: true, turnover: cost);
        return AlertDialog(
          title: Text('Buy ${widget.symbol}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: priceCtl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Buy price (₹)',
                    helperText: 'last ₹${lastPrice.toStringAsFixed(2)}',
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setLocal(() {}),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: qtyCtl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Quantity (whole shares)',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setLocal(() {}),
                ),
                const SizedBox(height: 8),
                Text('Cost ₹${cost.toStringAsFixed(2)} + fees ≈ '
                    '₹${fee.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Text('Cash available ₹${_inr(_cash, decimals: 2)}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: (qty > 0 && price > 0)
                  ? () => Navigator.pop(ctx, (qty: qty, price: price))
                  : null,
              child: const Text('Buy'),
            ),
          ],
        );
      }),
    );
    if (result == null) return;
    try {
      await _portfolio.buy(widget.symbol, result.qty, result.price);
      _snack('Bought ${result.qty} ${widget.symbol} @ '
          '₹${result.price.toStringAsFixed(2)}');
    } catch (e) {
      _snack(e is StateError ? e.message : 'Buy failed');
    }
  }

  Future<void> _showSell(Holding h, double price) async {
    final qtyCtl = TextEditingController(text: '${h.qty}');
    final qty = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        final q = int.tryParse(qtyCtl.text) ?? 0;
        final proceeds = q * price;
        final fee = Fees.forTrade(isBuy: false, turnover: proceeds);
        final pnl = (price - h.avgPrice) * q - fee;
        return AlertDialog(
          title: Text('Sell ${h.symbol}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('You hold ${h.qty} @ avg ₹${h.avgPrice.toStringAsFixed(2)}'),
              Text('Sell price: ₹${price.toStringAsFixed(2)}'),
              const SizedBox(height: 12),
              TextField(
                controller: qtyCtl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Quantity to sell',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setLocal(() {}),
              ),
              const SizedBox(height: 8),
              Text('Proceeds ₹${proceeds.toStringAsFixed(2)} − fees ≈ '
                  '₹${fee.toStringAsFixed(2)}'),
              Text(
                  'Realized P/L: ${pnl >= 0 ? '+' : ''}₹${pnl.toStringAsFixed(2)}',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: pnl >= 0 ? Colors.green : Colors.red)),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: (q > 0 && q <= h.qty) ? () => Navigator.pop(ctx, q) : null,
              child: const Text('Sell'),
            ),
          ],
        );
      }),
    );
    if (qty == null) return;
    try {
      await _portfolio.sell(h.symbol, qty, price);
      _snack('Sold $qty ${h.symbol}');
    } catch (e) {
      _snack(e is StateError ? e.message : 'Sell failed');
    }
  }

  // ---------------------------------------------------------------------------
  // Financials tab
  // ---------------------------------------------------------------------------

  /// Indian digit grouping: 1234567.8 -> "12,34,568".
  static String _inr(double v, {int decimals = 0}) {
    final neg = v < 0;
    final parts = v.abs().toStringAsFixed(decimals).split('.');
    var s = parts[0];
    if (s.length > 3) {
      final last3 = s.substring(s.length - 3);
      var rest = s.substring(0, s.length - 3);
      final groups = <String>[];
      while (rest.length > 2) {
        groups.insert(0, rest.substring(rest.length - 2));
        rest = rest.substring(0, rest.length - 2);
      }
      if (rest.isNotEmpty) groups.insert(0, rest);
      s = '${groups.join(',')},$last3';
    }
    final dec = parts.length > 1 ? '.${parts[1]}' : '';
    return '${neg ? '-' : ''}$s$dec';
  }

  /// ₹ crore amount, using lakh-crore for very large values.
  static String _cr(double? v) {
    if (v == null) return '—';
    if (v.abs() >= 100000) return '₹${(v / 100000).toStringAsFixed(2)} L Cr';
    return '₹${_inr(v)} Cr';
  }

  static String _pct(double? v, {bool signed = false}) => v == null
      ? '—'
      : '${signed && v > 0 ? '+' : ''}${v.toStringAsFixed(1)}%';

  static String _x(double? v, {int d = 2, String prefix = '', String suffix = ''}) =>
      v == null ? '—' : '$prefix${v.toStringAsFixed(d)}$suffix';

  static Color? _signColor(double? v) => v == null
      ? null
      : v >= 0
          ? Colors.green.shade700
          : Colors.red.shade700;

  Widget _buildFinancials() {
    if (_finLoading) return const Center(child: CircularProgressIndicator());
    if (_finError != null) {
      return Center(child: Text(_finError!, textAlign: TextAlign.center));
    }
    final f = _fin;
    if (f == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Financials not available yet for this stock.\n\n'
            'They are fetched in the background during market hours; '
            'check back in a few minutes.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final small = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: Colors.grey.shade700);
    final latestQ = f.quarterly.isNotEmpty ? f.quarterly.last : null;
    return RefreshIndicator(
      onRefresh: _loadFinancials,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (f.name != null)
            Text(f.name!,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          if (f.sector != null || f.industry != null)
            Text([f.sector, f.industry].whereType<String>().join(' · '),
                style: small),
          const SizedBox(height: 4),
          AgeLabel(
              iso: f.ts,
              prefix: 'Financials updated',
              staleAfter: const Duration(days: 8)),
          const SizedBox(height: 12),

          // Headline profit / loss.
          if (latestQ != null) _profitBanner(latestQ),
          const SizedBox(height: 12),

          _panelTitle('Key figures'),
          _statsGrid([
            ('Market cap', _cr(f.marketCapCr), null),
            ('P/E (TTM)', _x(f.pe, d: 1), null),
            ('EPS (TTM)', _x(f.eps, prefix: '₹'), _signColor(f.eps)),
            ('P/B', _x(f.pb), null),
            ('Revenue (TTM)', _cr(f.revenueTtmCr), null),
            ('Net profit (TTM)', _cr(f.netIncomeTtmCr), _signColor(f.netIncomeTtmCr)),
            ('Net margin', _pct(f.profitMargin), _signColor(f.profitMargin)),
            ('Operating margin', _pct(f.opMargin), _signColor(f.opMargin)),
            ('ROE', _pct(f.roe), _signColor(f.roe)),
            ('Debt / Equity', _x(f.debtToEquity, suffix: 'x'), null),
            ('Revenue growth (YoY)', _pct(f.revenueGrowth, signed: true),
                _signColor(f.revenueGrowth)),
            ('Profit growth (YoY)', _pct(f.earningsGrowth, signed: true),
                _signColor(f.earningsGrowth)),
            ('Dividend yield', _pct(f.divYield), null),
            ('Book value / share', _x(f.bookValue, prefix: '₹'), null),
            ('52-week high', _x(f.high52, prefix: '₹'), null),
            ('52-week low', _x(f.low52, prefix: '₹'), null),
          ]),
          const SizedBox(height: 16),

          if (f.quarterly.isNotEmpty) ...[
            _panelTitle('Quarterly net profit / loss (₹ Cr)'),
            _finBars(f.quarterly, (p) => p.netProfit, signColored: true),
            const SizedBox(height: 12),
            _panelTitle('Quarterly revenue (₹ Cr)'),
            _finBars(f.quarterly, (p) => p.revenue),
            const SizedBox(height: 12),
            _panelTitle('Quarterly results (₹ Cr)'),
            _finTable(f.quarterly),
            const SizedBox(height: 16),
          ],
          if (f.annual.isNotEmpty) ...[
            _panelTitle('Annual results (₹ Cr)'),
            _finTable(f.annual, showGrowth: true),
            const SizedBox(height: 16),
          ],
          Text(
            'Source: Yahoo Finance (consolidated where available). Some '
            'quarters may be missing. Not investment advice.',
            style: small,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// "Q Sep 26: Profit ₹25,548 Cr (margin 7.7%)" — green for profit, red for loss.
  Widget _profitBanner(FinPeriod q) {
    final np = q.netProfit;
    final isProfit = (np ?? 0) >= 0;
    final c = np == null
        ? Colors.grey
        : isProfit
            ? Colors.green.shade700
            : Colors.red.shade700;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(isProfit ? Icons.trending_up : Icons.trending_down, color: c),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Latest quarter (${q.period})',
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
                Text(
                  np == null
                      ? 'Net profit: —'
                      : '${isProfit ? 'Net profit' : 'Net loss'} '
                          '${_cr(np.abs())}',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold, color: c),
                ),
                Text(
                  'Revenue ${_cr(q.revenue)}'
                  '${q.netMargin != null ? ' · margin ${_pct(q.netMargin)}' : ''}',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statsGrid(List<(String, String, Color?)> items) {
    return LayoutBuilder(builder: (context, box) {
      // Web on a wide area gets 4 columns; the phone always gets 2.
      final cols = (isWideWeb(context) && box.maxWidth >= 640) ? 4 : 2;
      final w = (box.maxWidth - 8 * (cols - 1)) / cols;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (label, value, color) in items)
            Container(
              width: w,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  const SizedBox(height: 2),
                  Text(value,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: color)),
                ],
              ),
            ),
        ],
      );
    });
  }

  /// Bar chart of one value per period (supports negative = loss).
  Widget _finBars(List<FinPeriod> periods, double? Function(FinPeriod) value,
      {bool signColored = false}) {
    final vals = periods.map(value).toList();
    final present = vals.whereType<double>();
    if (present.isEmpty) {
      return const Text('No data', style: TextStyle(color: Colors.grey));
    }
    final maxV = present.reduce((a, b) => a > b ? a : b);
    final minV = present.reduce((a, b) => a < b ? a : b);
    final top = maxV > 0 ? maxV * 1.15 : 1.0;
    final bottom = minV < 0 ? minV * 1.15 : 0.0;
    return SizedBox(
      height: 150,
      child: BarChart(BarChartData(
        maxY: top,
        minY: bottom,
        barGroups: [
          for (var i = 0; i < vals.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: vals[i] ?? 0,
                width: 18,
                borderRadius: BorderRadius.circular(2),
                color: !signColored
                    ? Colors.blue.shade400
                    : (vals[i] ?? 0) >= 0
                        ? Colors.green.shade500
                        : Colors.red.shade400,
              ),
            ]),
        ],
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 52)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= periods.length) return const SizedBox();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(periods[i].period,
                      style: const TextStyle(fontSize: 10)),
                );
              },
            ),
          ),
        ),
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(
            show: true, border: Border.all(color: Colors.grey.shade300)),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => Colors.black87,
            getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(
              '${periods[group.x].period}\n'
              '${vals[group.x] == null ? '—' : _cr(vals[group.x])}',
              const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ),
      )),
    );
  }

  /// Period | Revenue | Op. profit | Net profit | Margin (| Profit growth).
  Widget _finTable(List<FinPeriod> periods, {bool showGrowth = false}) {
    const head = TextStyle(fontSize: 11, fontWeight: FontWeight.bold);
    const cell = TextStyle(fontSize: 12);
    Widget c(String t, {TextStyle style = cell, Color? color, bool left = false}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Text(t,
              textAlign: left ? TextAlign.left : TextAlign.right,
              style: color == null ? style : style.copyWith(color: color)),
        );
    String n(double? v) => v == null ? '—' : _inr(v);

    // Newest first in the table (charts read oldest → newest).
    final rows = periods.reversed.toList();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints:
            BoxConstraints(minWidth: MediaQuery.of(context).size.width - 24),
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          border: TableBorder(
              horizontalInside: BorderSide(color: Colors.grey.shade300)),
          children: [
            TableRow(
              decoration:
                  BoxDecoration(color: Colors.grey.withValues(alpha: 0.10)),
              children: [
                c('Period', style: head, left: true),
                c('Revenue', style: head),
                c('Op. profit', style: head),
                c('Net profit', style: head),
                c('Margin', style: head),
                if (showGrowth) c('Profit YoY', style: head),
              ],
            ),
            for (var i = 0; i < rows.length; i++)
              TableRow(children: [
                c(rows[i].period, left: true),
                c(n(rows[i].revenue)),
                c(n(rows[i].opProfit), color: _signColor(rows[i].opProfit)),
                c(n(rows[i].netProfit), color: _signColor(rows[i].netProfit)),
                c(_pct(rows[i].netMargin)),
                if (showGrowth)
                  () {
                    // rows is newest-first, so the previous year is i + 1.
                    final prev = i + 1 < rows.length ? rows[i + 1].netProfit : null;
                    final cur = rows[i].netProfit;
                    final g = (prev != null && cur != null && prev != 0)
                        ? (cur - prev) / prev.abs() * 100
                        : null;
                    return c(_pct(g, signed: true), color: _signColor(g));
                  }(),
              ]),
          ],
        ),
      ),
    );
  }
}
