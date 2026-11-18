import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/stock_data.dart';
import '../services/stock_service.dart';
import '../widgets/updated_at.dart';

class ChartScreen extends StatefulWidget {
  final String symbol;
  const ChartScreen({super.key, required this.symbol});

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

  @override
  void initState() {
    super.initState();
    _load();
    _loadFinancials();
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
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const UpdatedAtLabel(),
        if (full.dates.isNotEmpty)
          Text('Chart data to ${full.dates.last} close',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.grey.shade700)),
        const SizedBox(height: 8),
        _rangeSelector(),
        _panelTitle('Price · EMA50 · EMA200 · Bollinger'),
        _lineChart(
          height: 260,
          lines: [
            _line(_spots(d.bbUpper), Colors.grey.shade400, width: 1),
            _line(_spots(d.bbLower), Colors.grey.shade400, width: 1),
            _line(_spots(d.close), Colors.black, width: 1.6),
            _line(_spots(d.ema50), Colors.blue, width: 1.2),
            _line(_spots(d.ema200), Colors.red, width: 1.2),
          ],
          minY: _min([d.bbLower, d.close, d.ema200]) * 0.99,
          maxY: _max([d.bbUpper, d.close]) * 1.01,
          n: n,
          dates: d.dates,
          valuePrefix: '₹',
          primaryBarIndex: 2, // the Close line
        ),
        _legend(const {
          'Close': Colors.black,
          'EMA50': Colors.blue,
          'EMA200': Colors.red,
          'Bollinger': Colors.grey,
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
      ],
    );
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
  }) {
    final hLines = <HorizontalLine>[];
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
      final w = (box.maxWidth - 8) / 2;
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
